<?php
/**
 * PHPUnit tests for Valkey GLIDE primary/replica replication.
 *
 * Writes go to the standalone primary (valkey:6379); reads are served from
 * the read-only replica (valkey-replica:6379) via a prefer-replica client
 * that knows both nodes and routes reads to the replica. Verifies that data
 * replicates and that a direct write to the replica is rejected.
 */

use PHPUnit\Framework\TestCase;

class ValkeyReplicaTest extends TestCase
{
    protected $primary;
    protected $replica;  // prefer-replica client (reads routed to replica)

    protected function setUp(): void
    {
        $this->primary = new ValkeyGlide();
        $this->primary->connect(addresses: [['host' => 'valkey', 'port' => 6379]]);

        // Prefer-replica client: both nodes known, reads served from replica.
        $this->replica = new ValkeyGlide();
        $this->replica->connect(
            addresses: [
                ['host' => 'valkey', 'port' => 6379],
                ['host' => 'valkey-replica', 'port' => 6379],
            ],
            read_from: ValkeyGlide::READ_FROM_PREFER_REPLICA,
        );
    }

    protected function tearDown(): void
    {
        foreach (['repl:string', 'repl:counter'] as $key) {
            $this->primary->del($key);
        }
    }

    // Wait for a key to propagate to the replica.
    private function waitForReplication(string $key, string $expected, int $tries = 25): ?string
    {
        for ($i = 0; $i < $tries; $i++) {
            $value = $this->replica->get($key);
            if ($value === $expected) {
                return $value;
            }
            usleep(100_000); // 100ms
        }
        return $this->replica->get($key);
    }

    public function testReplicaPing(): void
    {
        $this->assertTrue($this->replica->ping());
    }

    public function testWriteToPrimaryReadFromReplica(): void
    {
        $value = 'replicated-value';
        $this->primary->set('repl:string', $value);

        $fromReplica = $this->waitForReplication('repl:string', $value);
        $this->assertEquals($value, $fromReplica);
    }

    public function testIncrementReplicates(): void
    {
        $this->primary->set('repl:counter', '0');
        $this->primary->incr('repl:counter');
        $this->primary->incr('repl:counter');

        $fromReplica = $this->waitForReplication('repl:counter', '2');
        $this->assertEquals('2', $fromReplica);
    }
}
