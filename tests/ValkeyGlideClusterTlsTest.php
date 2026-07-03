<?php
/**
 * PHPUnit tests for the AZ-aware Valkey cluster over TLS.
 *
 * Exercises the `tls`-profile cluster (formed by scripts/cluster-init-tls.sh):
 * 3 shards, each 1 primary + 1 replica in a DIFFERENT AZ (the realistic
 * Multi-AZ failover pattern) = 6 nodes. Both the client protocol AND the
 * cluster bus are TLS (--tls-cluster yes).
 *
 *   Shard 1  primary=us-east-1a  replica=us-east-1b
 *   Shard 2  primary=us-east-1b  replica=us-east-1c
 *   Shard 3  primary=us-east-1c  replica=us-east-1a
 *
 * The local certs are self-signed with no SAN, which rustls cannot verify, so
 * the GLIDE client connects with `advanced_config.tls_config.use_insecure_tls`
 * — encrypted, but server-cert verification skipped (local dev only). phpredis
 * (used for per-node stats) connects with the `tls://` scheme and peer
 * verification disabled for the same reason.
 *
 * Requires the tls profile:
 *   ./certs/gen-test-certs.sh
 *   docker compose --profile tls up -d --build
 */

use PHPUnit\Framework\TestCase;

class ValkeyGlideClusterTlsTest extends TestCase
{
    // Seed nodes — the 3 shard primaries. GLIDE discovers the replicas.
    private const SEEDS = [
        ['host' => 'vk-tls-s1-1a-p', 'port' => 6379],
        ['host' => 'vk-tls-s2-1b-p', 'port' => 6379],
        ['host' => 'vk-tls-s3-1c-p', 'port' => 6379],
    ];

    private const AZS = ['us-east-1a', 'us-east-1b', 'us-east-1c'];

    // Encrypted but skip verification (test certs have no SAN).
    private const TLS = ['tls_config' => ['use_insecure_tls' => true]];

    // phpredis stream context: TLS with peer verification disabled.
    private const PHPREDIS_TLS = ['stream' => ['verify_peer' => false, 'verify_peer_name' => false]];

    private ValkeyGlideCluster $client;

    protected function setUp(): void
    {
        $this->client = self::makeClient('us-east-1a', ValkeyGlide::READ_FROM_AZ_AFFINITY);
    }

    protected function tearDown(): void
    {
        $keys = [
            'greeting', '{tls}:red', '{tls}:green', '{tls}:blue',
            'tls:cross:user', 'tls:cross:order', 'tls:cross:product',
            'tls:cross:session', 'tls:cross:cache', 'tls:cross:metric',
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
            use_tls: true,
            request_timeout: 3000,
            advanced_config: self::TLS,
            read_from: $readFrom,
            client_az: $az,
        );
    }

    // Standalone GLIDE probe to a single node over TLS (for CLUSTER commands,
    // which the cluster client doesn't route to one node cleanly).
    private static function probe(string $host = 'vk-tls-s1-1a-p'): ValkeyGlide
    {
        $p = new ValkeyGlide();
        $p->connect(
            addresses: [['host' => $host, 'port' => 6379]],
            use_tls: true,
            request_timeout: 3000,
            advanced_config: self::TLS,
        );
        return $p;
    }

    // Direct single-node admin connection over TLS via phpredis. GLIDE refuses
    // to connect a standalone client to a replica ("No primary node found"),
    // so per-node stats go through phpredis with the tls:// scheme.
    private static function adminNode(string $host, int $port): Redis
    {
        $c = new Redis();
        $c->connect("tls://$host", $port, 3, null, 0, 0, self::PHPREDIS_TLS);
        return $c;
    }

    // Resolve a node's AZ from its running config over TLS.
    private static function azOf(string $host, int $port): string
    {
        $res = self::adminNode($host, $port)->rawCommand('CONFIG', 'GET', 'availability-zone');
        return is_array($res) ? (string) ($res[1] ?? '') : (string) $res;
    }

    // =========================================================================
    // Connectivity + basic ops over TLS
    // =========================================================================

    public function testPingOverTls(): void
    {
        // Bare ping() has no single node to target on a cluster client; ping
        // with a message round-trips through a node.
        $this->assertTrue($this->client->ping('hello'));
    }

    public function testSetAndGetOverTls(): void
    {
        $this->client->set('greeting', 'Hello over TLS cluster!');
        $this->assertEquals('Hello over TLS cluster!', $this->client->get('greeting'));
    }

    public function testMsetMgetSameSlotOverTls(): void
    {
        $this->client->mset([
            '{tls}:red' => '#FF0000',
            '{tls}:green' => '#00FF00',
            '{tls}:blue' => '#0000FF',
        ]);
        $colors = $this->client->mget(['{tls}:red', '{tls}:green', '{tls}:blue']);
        $this->assertEquals(['#FF0000', '#00FF00', '#0000FF'], $colors);
    }

    // GLIDE transparently splits a cross-slot mset/mget across shards — over
    // TLS just as in plaintext.
    public function testCrossSlotMsetMgetOverTls(): void
    {
        $keys = [
            'tls:cross:user', 'tls:cross:order', 'tls:cross:product',
            'tls:cross:session', 'tls:cross:cache', 'tls:cross:metric',
        ];
        $pairs = [];
        foreach ($keys as $k) {
            $pairs[$k] = "val_$k";
        }

        $this->client->mset($pairs);
        $values = $this->client->mget($keys);

        $this->assertCount(count($keys), $values);
        foreach ($keys as $i => $k) {
            $this->assertSame("val_$k", $values[$i], "mget[$i] ($k) mismatch");
        }
    }

    // =========================================================================
    // Topology: 3 shards, 1 primary + 1 cross-AZ replica each (6 nodes)
    // =========================================================================

    public function testClusterStateOkOverTls(): void
    {
        $info = (string) self::probe()->rawcommand('CLUSTER', 'INFO');
        $this->assertStringContainsString('cluster_state:ok', $info);
    }

    public function testTopologyIsThreeShardsSixNodes(): void
    {
        $nodes = (string) self::probe()->rawcommand('CLUSTER', 'NODES');
        $lines = array_values(array_filter(explode("\n", trim($nodes))));
        $this->assertCount(6, $lines, 'expected 6 cluster nodes');

        $masters = array_filter($lines, fn($l) => str_contains($l, 'master'));
        $replicas = array_filter($lines, fn($l) => str_contains($l, 'slave'));
        $this->assertCount(3, $masters, 'expected 3 primaries');
        $this->assertCount(3, $replicas, 'expected 3 replicas');
    }

    // Multi-AZ pattern: each shard's replica must sit in a DIFFERENT AZ from
    // its primary (the whole point of the TLS cluster's placement).
    public function testEachReplicaInDifferentAzThanPrimary(): void
    {
        $shards = $this->readShards();
        $this->assertCount(3, $shards, 'expected 3 shards');

        $primaryAzs = [];
        foreach ($shards as $shortId => $shard) {
            $this->assertNotNull($shard['primary'], "shard $shortId has no primary");
            $this->assertCount(1, $shard['replicas'], "shard $shortId must have exactly 1 replica");

            $primaryAz = $shard['primary']['az'];
            $replicaAz = $shard['replicas'][0]['az'];
            $this->assertNotSame(
                $primaryAz,
                $replicaAz,
                "shard $shortId replica must be in a different AZ than its primary ($primaryAz)"
            );
            $primaryAzs[] = $primaryAz;
        }

        // Primaries span all 3 AZs, one per AZ.
        sort($primaryAzs);
        $this->assertSame(self::AZS, $primaryAzs, 'primaries must span all 3 AZs one-per-AZ');
    }

    // READ_FROM_PRIMARY must send zero GETs to replicas, even over TLS.
    public function testReadFromPrimaryOverTls(): void
    {
        $nodes = $this->readNodes();
        $client = self::makeClient('us-east-1a', ValkeyGlide::READ_FROM_PRIMARY);

        foreach ($nodes as $n) {
            self::adminNode($n['host'], $n['port'])->rawCommand('CONFIG', 'RESETSTAT');
        }

        $client->set('greeting', 'primary-only');
        for ($i = 0; $i < 30; $i++) {
            $client->get('greeting');
        }

        $replicaGets = 0;
        foreach ($nodes as $n) {
            if ($n['role'] === 'slave') {
                $replicaGets += self::getCmdCount(self::adminNode($n['host'], $n['port']));
            }
        }
        $client->del('greeting');

        $this->assertSame(0, $replicaGets, 'READ_FROM_PRIMARY should send zero GETs to replicas');
    }

    // =========================================================================
    // Helpers
    // =========================================================================

    // Parse CLUSTER NODES into shards keyed by short primary node-id.
    private function readShards(): array
    {
        $raw = (string) self::probe()->rawcommand('CLUSTER', 'NODES');

        $shards = [];
        foreach (array_filter(explode("\n", trim($raw))) as $line) {
            $f = preg_split('/\s+/', trim($line));
            $id       = $f[0];
            $masterId = $f[3];
            [$host, $port] = explode(':', explode('@', $f[1])[0]);
            $node = ['host' => $host, 'port' => (int) $port, 'az' => self::azOf($host, (int) $port)];

            $shardId = substr(($masterId === '-') ? $id : $masterId, 0, 8);
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

    // Flat list of nodes: ['host','port','az','role'].
    private function readNodes(): array
    {
        $raw = (string) self::probe()->rawcommand('CLUSTER', 'NODES');
        $nodes = [];
        foreach (array_filter(explode("\n", trim($raw))) as $line) {
            $f = preg_split('/\s+/', trim($line));
            [$host, $port] = explode(':', explode('@', $f[1])[0]);
            $role = str_contains($f[2], 'master') ? 'master' : 'slave';
            $nodes[] = [
                'host' => $host,
                'port' => (int) $port,
                'az'   => self::azOf($host, (int) $port),
                'role' => $role,
            ];
        }
        return $nodes;
    }

    private static function getCmdCount(Redis $node): int
    {
        $stats = $node->info('commandstats');
        $line = is_array($stats) ? ($stats['cmdstat_get'] ?? '') : '';
        if (preg_match('/calls=(\d+)/', (string) $line, $m)) {
            return (int) $m[1];
        }
        return 0;
    }
}
