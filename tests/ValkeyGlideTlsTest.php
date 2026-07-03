<?php
/**
 * PHPUnit tests for Valkey GLIDE over TLS (standalone primary + replica).
 *
 * Exercises the `tls`-profile services valkey-tls (primary, host 6390) and
 * valkey-tls-replica (host 6391). Both listen ONLY on the TLS port, so the
 * GLIDE client must connect with use_tls:true. The local certs are self-signed
 * with no SAN, which rustls cannot verify, so we connect with
 * `advanced_config.tls_config.use_insecure_tls` — the connection is still
 * encrypted, only server-cert verification is skipped (fine for local dev).
 *
 * Mirrors ValkeyReplicaTest but over TLS: writes go to the primary, reads are
 * served from the replica via a prefer-replica client, and we confirm data
 * replicates across the encrypted link.
 *
 * Requires the tls profile:
 *   ./certs/gen-test-certs.sh
 *   docker compose --profile tls up -d --build
 */

use PHPUnit\Framework\TestCase;

class ValkeyGlideTlsTest extends TestCase
{
    // Encrypted, but skip cert verification: the test certs have no SAN so
    // rustls can't verify them. Flip to a verifying config once certs carry
    // a proper subjectAltName.
    private const TLS = ['tls_config' => ['use_insecure_tls' => true]];

    protected ValkeyGlide $primary;
    protected ValkeyGlide $replica;  // prefer-replica client (reads from replica)

    protected function setUp(): void
    {
        $this->primary = new ValkeyGlide();
        $this->primary->connect(
            addresses: [['host' => 'valkey-tls', 'port' => 6379]],
            use_tls: true,
            request_timeout: 3000,
            advanced_config: self::TLS,
        );

        // Prefer-replica client: both nodes known, reads served from replica.
        $this->replica = new ValkeyGlide();
        $this->replica->connect(
            addresses: [
                ['host' => 'valkey-tls', 'port' => 6379],
                ['host' => 'valkey-tls-replica', 'port' => 6379],
            ],
            use_tls: true,
            request_timeout: 3000,
            advanced_config: self::TLS,
            read_from: ValkeyGlide::READ_FROM_PREFER_REPLICA,
        );
    }

    protected function tearDown(): void
    {
        foreach (['tls:string', 'tls:counter', 'tls:hash'] as $key) {
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

    public function testPrimaryPingOverTls(): void
    {
        $this->assertTrue($this->primary->ping());
    }

    public function testReplicaPingOverTls(): void
    {
        $this->assertTrue($this->replica->ping());
    }

    public function testSetAndGetOverTls(): void
    {
        $this->primary->set('tls:string', 'encrypted-hello');
        $this->assertEquals('encrypted-hello', $this->primary->get('tls:string'));
    }

    public function testHashOpsOverTls(): void
    {
        $this->primary->hset('tls:hash', 'name', 'Alice');
        $this->primary->hset('tls:hash', 'role', 'admin');
        $all = $this->primary->hgetall('tls:hash');
        $this->assertEquals('Alice', $all['name']);
        $this->assertEquals('admin', $all['role']);
    }

    public function testWriteToPrimaryReadFromReplicaOverTls(): void
    {
        $value = 'replicated-over-tls';
        $this->primary->set('tls:string', $value);

        $fromReplica = $this->waitForReplication('tls:string', $value);
        $this->assertEquals($value, $fromReplica);
    }

    public function testIncrementReplicatesOverTls(): void
    {
        $this->primary->set('tls:counter', '0');
        $this->primary->incr('tls:counter');
        $this->primary->incr('tls:counter');

        $fromReplica = $this->waitForReplication('tls:counter', '2');
        $this->assertEquals('2', $fromReplica);
    }

    // The connection is genuinely TLS: the server advertises a TLS listener
    // (INFO server reports `listenerN:name=tls,...`). Confirms we're not
    // silently talking plaintext.
    public function testServerAdvertisesTlsListener(): void
    {
        $info = (string) $this->primary->rawcommand('INFO', 'server');
        $this->assertMatchesRegularExpression('/name=tls/', $info, 'server should advertise a TLS listener');
    }
}
