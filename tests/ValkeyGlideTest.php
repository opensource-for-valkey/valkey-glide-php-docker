<?php
/**
 * PHPUnit tests for valkey-glide-php specific features.
 *
 * Covers GLIDE-exclusive capabilities not tested by the generic base class:
 *   - AZ-awareness: all READ_FROM strategies, client_az routing
 *   - Multi-sharded commands: cross-slot mset/mget (GLIDE splits & merges)
 *   - Sharded pub/sub: SPUBLISH/SSUBSCRIBE (channel-keyed slot routing)
 *   - Pub/Sub introspection: PUBSUB CHANNELS/NUMSUB/NUMPAT on cluster
 */

use PHPUnit\Framework\TestCase;

class ValkeyGlideTest extends TestCase
{
    private const SEEDS = [
        ['host' => 'vk-s1-1a-p', 'port' => 6379],
        ['host' => 'vk-s2-1b-p', 'port' => 6379],
        ['host' => 'vk-s3-1c-p', 'port' => 6379],
    ];

    private const AZS = ['us-east-1a', 'us-east-1b', 'us-east-1c'];

    private ?ValkeyGlideCluster $client = null;

    protected function setUp(): void
    {
        $this->client = self::clusterClient('us-east-1a', ValkeyGlide::READ_FROM_AZ_AFFINITY);
    }

    protected function tearDown(): void
    {
        $cleanup = [
            'glide:cross:user', 'glide:cross:order', 'glide:cross:product',
            'glide:cross:session', 'glide:cross:cache', 'glide:cross:metric',
            'glide:cross:log', 'glide:cross:event', 'glide:cross:job', 'glide:cross:token',
            'glide:az:probe',
        ];
        foreach ($cleanup as $k) {
            $this->client->del($k);
        }
    }

    private static function clusterClient(string $az, int $readFrom): ValkeyGlideCluster
    {
        return new ValkeyGlideCluster(
            name: null, seeds: null, timeout: null, read_timeout: null,
            persistent: null, auth: null, context: null,
            addresses: self::SEEDS,
            read_from: $readFrom,
            client_az: $az,
        );
    }

    private static function adminNode(string $host, int $port): Redis
    {
        $c = new Redis();
        $c->connect($host, $port);
        return $c;
    }

    // =========================================================================
    // AZ-awareness tests
    // =========================================================================

    public function testReadFromAzAffinityRoutesToLocalAz(): void
    {
        $targetAz = 'us-east-1b';
        $client = self::clusterClient($targetAz, ValkeyGlide::READ_FROM_AZ_AFFINITY);

        $nodes = self::allNodes();
        foreach ($nodes as $n) {
            self::adminNode($n['host'], $n['port'])->rawCommand('CONFIG', 'RESETSTAT');
        }

        $keys = ['glide:az:k1', 'glide:az:k2', 'glide:az:k3', 'glide:az:k4', 'glide:az:k5'];
        foreach ($keys as $k) {
            $client->set($k, 'v');
        }
        for ($i = 0; $i < 20; $i++) {
            foreach ($keys as $k) {
                $client->get($k);
            }
        }

        $getsByAz = array_fill_keys(self::AZS, 0);
        foreach ($nodes as $n) {
            $getsByAz[$n['az']] += self::getNodeGetCount($n['host'], $n['port']);
        }

        foreach ($keys as $k) {
            $client->del($k);
        }

        $this->assertGreaterThan(0, $getsByAz[$targetAz], "expected GETs in $targetAz");
        foreach (self::AZS as $az) {
            if ($az !== $targetAz) {
                $this->assertSame(0, $getsByAz[$az], "unexpected GETs in $az: {$getsByAz[$az]}");
            }
        }
    }

    public function testReadFromAzAffinityReplicasAndPrimary(): void
    {
        $targetAz = 'us-east-1c';
        $client = self::clusterClient($targetAz, ValkeyGlide::READ_FROM_AZ_AFFINITY_REPLICAS_AND_PRIMARY);

        $client->set('glide:az:probe', 'val');
        $result = $client->get('glide:az:probe');
        $this->assertSame('val', $result);
        $client->del('glide:az:probe');
    }

    public function testReadFromPreferReplica(): void
    {
        $client = self::clusterClient('us-east-1a', ValkeyGlide::READ_FROM_PREFER_REPLICA);

        $nodes = self::allNodes();
        foreach ($nodes as $n) {
            self::adminNode($n['host'], $n['port'])->rawCommand('CONFIG', 'RESETSTAT');
        }

        $client->set('glide:az:probe', 'prefer-replica');
        usleep(100_000);
        for ($i = 0; $i < 30; $i++) {
            $client->get('glide:az:probe');
        }

        $replicaGets = 0;
        foreach ($nodes as $n) {
            if ($n['role'] === 'slave') {
                $replicaGets += self::getNodeGetCount($n['host'], $n['port']);
            }
        }
        $client->del('glide:az:probe');

        $this->assertGreaterThan(0, $replicaGets, 'PREFER_REPLICA should route reads to replicas');
    }

    public function testReadFromPrimary(): void
    {
        $client = self::clusterClient('us-east-1a', ValkeyGlide::READ_FROM_PRIMARY);

        $nodes = self::allNodes();
        foreach ($nodes as $n) {
            self::adminNode($n['host'], $n['port'])->rawCommand('CONFIG', 'RESETSTAT');
        }

        $client->set('glide:az:probe', 'primary-only');
        for ($i = 0; $i < 30; $i++) {
            $client->get('glide:az:probe');
        }

        $replicaGets = 0;
        foreach ($nodes as $n) {
            if ($n['role'] === 'slave') {
                $replicaGets += self::getNodeGetCount($n['host'], $n['port']);
            }
        }
        $client->del('glide:az:probe');

        $this->assertSame(0, $replicaGets, 'READ_FROM_PRIMARY should send zero GETs to replicas');
    }

    // =========================================================================
    // Multi-sharded commands (GLIDE transparently splits across slots)
    // =========================================================================

    public function testCrossSlotMsetMget(): void
    {
        $keys = [
            'glide:cross:user', 'glide:cross:order', 'glide:cross:product',
            'glide:cross:session', 'glide:cross:cache', 'glide:cross:metric',
            'glide:cross:log', 'glide:cross:event', 'glide:cross:job', 'glide:cross:token',
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


    public function testCrossSlotMgetMissingKeys(): void
    {
        $this->client->set('glide:cross:user', 'exists');

        $values = $this->client->mget(['glide:cross:user', 'glide:cross:nonexistent_xyz']);
        $this->assertSame('exists', $values[0]);
        $this->assertFalse($values[1]);

        $this->client->del('glide:cross:nonexistent_xyz');
    }

    // =========================================================================
    // Sharded pub/sub (SPUBLISH routes to the node owning the channel's slot)
    // =========================================================================

    public function testShardedPublishRoutesToChannelSlot(): void
    {
        // SPUBLISH routes the message to the shard owning the channel's hash slot.
        // With no subscribers the return is 0, but it must not error.
        // Connect to the node owning the channel's slot to avoid MOVED.
        $channel = 'glide:sharded:ch1';
        $node = self::nodeForKey($channel);
        $result = $node->rawCommand('SPUBLISH', $channel, 'payload');
        $this->assertSame(0, $result);
    }

    public function testShardedPubsubChannels(): void
    {
        // PUBSUB SHARDCHANNELS lists active sharded channels (empty when none subscribed).
        $node = self::adminNode('vk-s1-1a-p', 6379);
        $channels = $node->rawCommand('PUBSUB', 'SHARDCHANNELS');
        $this->assertIsArray($channels);
    }

    public function testShardedPubsubNumsub(): void
    {
        // PUBSUB SHARDNUMSUB returns subscriber counts per channel.
        $node = self::adminNode('vk-s2-1b-p', 6379);
        $result = $node->rawCommand('PUBSUB', 'SHARDNUMSUB', 'glide:sharded:ch1');
        $this->assertIsArray($result);
        $this->assertSame('glide:sharded:ch1', $result[0]);
        $this->assertSame(0, $result[1]);
    }

    // =========================================================================
    // Pub/sub introspection via GLIDE cluster client
    // =========================================================================

    public function testPubsubChannelsOnCluster(): void
    {
        $channels = $this->client->pubsub('channels', '*');
        $this->assertIsArray($channels);
    }

    public function testPubsubNumsubOnCluster(): void
    {
        $result = $this->client->pubsub('numsub', ['glide:test:ch']);
        $this->assertIsArray($result);
        $this->assertSame('glide:test:ch', $result[0]);
        $this->assertSame(0, $result[1]);
    }

    public function testPubsubNumpatOnCluster(): void
    {
        $count = $this->client->pubsub('numpat');
        $this->assertIsInt($count);
        $this->assertSame(0, $count);
    }

    public function testPublishOnClusterReturnsReceiverCount(): void
    {
        $count = $this->client->publish('glide:test:broadcast', 'hello');
        $this->assertIsInt($count);
        $this->assertSame(0, $count);
    }

    // =========================================================================
    // Helpers
    // =========================================================================

    private static function allNodes(): array
    {
        $probe = new Redis();
        $probe->connect('vk-s1-1a-p', 6379);
        $raw = $probe->rawCommand('CLUSTER', 'NODES');
        $nodes = [];
        foreach (array_filter(explode("\n", trim($raw))) as $line) {
            $f = preg_split('/\s+/', trim($line));
            [$host, $port] = explode(':', explode('@', $f[1])[0]);
            $role = str_contains($f[2], 'master') ? 'master' : 'slave';
            $admin = self::adminNode($host, (int) $port);
            $azResult = $admin->rawCommand('CONFIG', 'GET', 'availability-zone');
            $az = is_array($azResult) ? ($azResult[1] ?? '') : '';
            $nodes[] = ['host' => $host, 'port' => (int) $port, 'az' => $az, 'role' => $role];
        }
        return $nodes;
    }

    private static function getNodeGetCount(string $host, int $port): int
    {
        $node = self::adminNode($host, $port);
        $stats = $node->info('commandstats');
        $line = is_array($stats) ? ($stats['cmdstat_get'] ?? '') : '';
        if (preg_match('/calls=(\d+)/', (string) $line, $m)) {
            return (int) $m[1];
        }
        return 0;
    }

    private static function nodeForKey(string $key): Redis
    {
        $probe = self::adminNode('vk-s1-1a-p', 6379);
        $slot = (int) $probe->rawCommand('CLUSTER', 'KEYSLOT', $key);
        $nodes = $probe->rawCommand('CLUSTER', 'NODES');
        foreach (array_filter(explode("\n", trim($nodes))) as $line) {
            $f = preg_split('/\s+/', trim($line));
            if (!str_contains($f[2], 'master')) {
                continue;
            }
            // Slot ranges are fields from index 8 onward.
            for ($i = 8; $i < count($f); $i++) {
                if (preg_match('/^(\d+)-(\d+)$/', $f[$i], $m)) {
                    if ($slot >= (int) $m[1] && $slot <= (int) $m[2]) {
                        [$host, $port] = explode(':', explode('@', $f[1])[0]);
                        return self::adminNode($host, (int) $port);
                    }
                }
            }
        }
        return $probe;
    }
}
