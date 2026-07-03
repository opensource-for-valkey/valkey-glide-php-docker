<?php
/**
 * PHPUnit tests for the AZ-aware Valkey cluster.
 *
 * Topology (formed by scripts/cluster-init.sh): 3 shards, each with 1
 * primary + 3 replicas spread one-per-AZ across us-east-1a/1b/1c = 12
 * nodes. Because every AZ holds a node for every shard, an AZ-affinity
 * client (READ_FROM_AZ_AFFINITY + client_az) always reads from a node in
 * its own AZ.
 *
 * Reuses the shared operation tests from ValkeyTestBase against the
 * cluster, then adds cluster-specific checks: topology shape and that
 * AZ-affinity reads are actually served from the client's own AZ.
 *
 * Note: multi-key commands (mset/mget) must land in one slot on a cluster,
 * so the inherited versions using differently-hashed keys are overridden
 * here with hash-tagged keys ({colors}).
 */

require_once __DIR__ . '/ValkeyTestBase.php';

class ValkeyClusterTest extends ValkeyTestBase
{
    // Seed nodes — the primaries, one per AZ. GLIDE discovers the rest.
    private const SEEDS = [
        ['host' => 'vk-s1-1a-p', 'port' => 6379],
        ['host' => 'vk-s2-1b-p', 'port' => 6379],
        ['host' => 'vk-s3-1c-p', 'port' => 6379],
    ];

    private const AZS = ['us-east-1a', 'us-east-1b', 'us-east-1c'];

    protected function setUp(): void
    {
        // Client pinned to us-east-1a with AZ-affinity read routing.
        $this->client = self::makeClient('us-east-1a', ValkeyGlide::READ_FROM_AZ_AFFINITY);
    }

    protected function tearDown(): void
    {
        $keys = [
            'greeting', 'session:abc123', 'counter',
            '{colors}:red', '{colors}:green', '{colors}:blue',
            'user:1', 'task_queue', 'online_users', 'leaderboard',
        ];
        foreach ($keys as $key) {
            $this->client->del($key);
        }
    }

    private static function makeClient(string $az, int $readFrom): ValkeyGlideCluster
    {
        return new ValkeyGlideCluster(
            name: null, seeds: null, timeout: null, read_timeout: null,
            persistent: null, auth: null, context: null,
            addresses: self::SEEDS,
            read_from: $readFrom,
            client_az: $az,
        );
    }

    // --- Overrides for cluster (multi-key ops must share one slot) --------

    // On the cluster client a bare ping() has no single node to target and
    // returns false; ping with a message round-trips through a node.
    public function testPing(): void
    {
        $this->assertTrue($this->client->ping('hello'));
    }

    public function testMsetMget(): void
    {
        $this->client->mset([
            '{colors}:red' => '#FF0000',
            '{colors}:green' => '#00FF00',
            '{colors}:blue' => '#0000FF',
        ]);
        $colors = $this->client->mget(['{colors}:red', '{colors}:green', '{colors}:blue']);
        $this->assertEquals(['#FF0000', '#00FF00', '#0000FF'], $colors);
    }

    // --- Cluster-specific tests -------------------------------------------

    // 3 primaries + 9 replicas = 12 known nodes, all slots covered.
    public function testTopologyIsThreeShardsTwelveNodes(): void
    {
        $probe = new ValkeyGlide();
        $probe->connect(addresses: [['host' => 'vk-s1-1a-p', 'port' => 6379]]);

        $info = (string) $probe->rawcommand('CLUSTER', 'INFO');
        $this->assertStringContainsString('cluster_state:ok', $info);

        $nodes = (string) $probe->rawcommand('CLUSTER', 'NODES');
        $lines = array_values(array_filter(explode("\n", trim($nodes))));
        $this->assertCount(12, $lines, 'expected 12 cluster nodes');

        $masters = array_filter($lines, fn($l) => str_contains($l, 'master'));
        $replicas = array_filter($lines, fn($l) => str_contains($l, 'slave'));
        $this->assertCount(3, $masters, 'expected 3 primaries');
        $this->assertCount(9, $replicas, 'expected 9 replicas');
    }

    // Precise AZ spread: 3 shards, each = 1 primary + 3 replicas, where the
    // 3 replicas cover all 3 AZs exactly once each, and the 3 primaries span
    // all 3 AZs one-per-AZ. This is the N+1-per-AZ guarantee that makes
    // AZ-affinity reads always local, enforced by scripts/cluster-init.sh.
    public function testEachShardSpreadsOneReplicaPerAz(): void
    {
        $shards = $this->readShards();

        $this->assertCount(3, $shards, 'expected 3 shards (one per primary)');

        $primaryAzs = [];
        foreach ($shards as $masterId => $shard) {
            $short = substr($masterId, 0, 8);

            // Each shard: exactly 1 primary + 3 replicas.
            $this->assertNotNull($shard['primary'], "shard $short has no primary");
            $this->assertCount(3, $shard['replicas'], "shard $short must have 3 replicas");

            // The 3 replicas cover all 3 AZs exactly once each.
            $replicaAzs = array_map(fn($r) => $r['az'], $shard['replicas']);
            sort($replicaAzs);
            $this->assertSame(
                self::AZS,
                $replicaAzs,
                "shard $short replicas must be one-per-AZ, got: " . implode(',', $replicaAzs)
            );

            $primaryAzs[] = $shard['primary']['az'];
        }

        // Primaries are spread one per AZ across the 3 shards.
        sort($primaryAzs);
        $this->assertSame(
            self::AZS,
            $primaryAzs,
            'primaries must span all 3 AZs one-per-AZ, got: ' . implode(',', $primaryAzs)
        );
    }

    // AZ affinity: reads issued by a client pinned to AZ X must be served
    // by nodes in AZ X. We reset per-node command stats, drive reads, then
    // assert only the pinned AZ's nodes recorded GETs.
    public function testAzAffinityRoutesReadsToLocalAz(): void
    {
        $probe = new ValkeyGlide();
        $probe->connect(addresses: [['host' => 'vk-s1-1a-p', 'port' => 6379]]);

        // Map every node address -> its availability zone.
        $nodesRaw = (string) $probe->rawcommand('CLUSTER', 'NODES');
        $nodes = [];
        foreach (array_filter(explode("\n", trim($nodesRaw))) as $line) {
            $f = preg_split('/\s+/', trim($line));
            [$host, $port] = explode(':', explode('@', $f[1])[0]);
            $az = self::azOf($host, (int) $port);
            $nodes[] = ['host' => $host, 'port' => (int) $port, 'az' => $az];
        }
        $this->assertCount(12, $nodes);

        $targetAz = 'us-east-1c';
        $client = self::makeClient($targetAz, ValkeyGlide::READ_FROM_AZ_AFFINITY);

        // Reset stats on every node.
        foreach ($nodes as $n) {
            self::adminNode($n['host'], $n['port'])->rawCommand('CONFIG', 'RESETSTAT');
        }

        // Drive reads across keys that hash to different shards.
        $keys = ['k1', 'k2', 'k3', 'foo', 'bar', 'baz', 'alpha', 'beta', 'gamma'];
        foreach ($keys as $k) {
            $client->set($k, 'v');
        }
        for ($i = 0; $i < 30; $i++) {
            foreach ($keys as $k) {
                $client->get($k);
            }
        }

        // Tally GETs per AZ.
        $getsByAz = array_fill_keys(self::AZS, 0);
        foreach ($nodes as $n) {
            $gets = self::getCmdCount(self::adminNode($n['host'], $n['port']));
            $getsByAz[$n['az']] += $gets;
        }

        foreach ($keys as $k) {
            $client->del($k);
        }

        $this->assertGreaterThan(0, $getsByAz[$targetAz], 'expected reads in the pinned AZ');
        foreach (self::AZS as $az) {
            if ($az === $targetAz) {
                continue;
            }
            $this->assertSame(0, $getsByAz[$az], "no reads expected in $az, got {$getsByAz[$az]}");
        }
    }

    // Parse CLUSTER NODES into shards keyed by primary node-id. Each entry:
    //   ['primary' => ['host','port','az'], 'replicas' => [ ...same... ]].
    // CLUSTER NODES line: <id> <ip:port@cport> <flags> <master-id|-> ...
    // For a primary the master-id field is '-'; for a replica it is the id
    // of the primary it follows.
    private function readShards(): array
    {
        $probe = new ValkeyGlide();
        $probe->connect(addresses: [['host' => 'vk-s1-1a-p', 'port' => 6379]]);
        $raw = (string) $probe->rawcommand('CLUSTER', 'NODES');

        $shards = [];
        foreach (array_filter(explode("\n", trim($raw))) as $line) {
            $f = preg_split('/\s+/', trim($line));
            $id       = $f[0];
            $masterId = $f[3];
            [$host, $port] = explode(':', explode('@', $f[1])[0]);
            $node = ['host' => $host, 'port' => (int) $port, 'az' => self::azOf($host, (int) $port)];

            $shardId = ($masterId === '-') ? $id : $masterId;
            if (!isset($shards[$shardId])) {
                $shards[$shardId] = ['primary' => null, 'replicas' => []];
            }
            if ($masterId === '-') {
                $shards[$shardId]['primary'] = $node;
            } else {
                $shards[$shardId]['replicas'][] = $node;
            }
        }
        return $shards;
    }

    // Resolve a node's AZ from its running config (CONFIG GET availability-zone).
    private static function azOf(string $host, int $port): string
    {
        // rawCommand returns a flat [name, value] pair.
        $res = self::adminNode($host, $port)->rawCommand('CONFIG', 'GET', 'availability-zone');
        return is_array($res) ? (string) ($res[1] ?? '') : (string) $res;
    }

    // Direct single-node admin connection. Uses phpredis (ext-redis) rather
    // than GLIDE: a standalone GLIDE client refuses to connect to a replica
    // cluster node ("No primary node found"), but we need per-node stats.
    private static function adminNode(string $host, int $port): Redis
    {
        $c = new Redis();
        $c->connect($host, $port);
        return $c;
    }

    private static function getCmdCount(Redis $node): int
    {
        // info('commandstats') returns e.g. ['cmdstat_get' => 'calls=42,usec=...'].
        $stats = $node->info('commandstats');
        $line = is_array($stats) ? ($stats['cmdstat_get'] ?? '') : '';
        if (preg_match('/calls=(\d+)/', (string) $line, $m)) {
            return (int) $m[1];
        }
        return 0;
    }
}
