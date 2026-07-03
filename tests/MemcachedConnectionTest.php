<?php
/**
 * PHPUnit tests for PHP -> Memcached connectivity via ext-memcached.
 *
 * Connects to the memcached service (defaults match the compose service
 * name/port) and verifies set/get, delete, and numeric increment.
 */

use PHPUnit\Framework\TestCase;

class MemcachedConnectionTest extends TestCase
{
    protected Memcached $mc;

    protected function setUp(): void
    {
        $host = getenv('MEMCACHED_HOST') ?: 'memcached';
        $port = (int) (getenv('MEMCACHED_PORT') ?: 11211);

        $this->mc = new Memcached();
        $this->mc->addServer($host, $port);
    }

    protected function tearDown(): void
    {
        foreach (['mc:greeting', 'mc:counter'] as $key) {
            $this->mc->delete($key);
        }
    }

    public function testConnectionIsEstablished(): void
    {
        // A live server responds to version() with a non-empty map.
        $versions = $this->mc->getVersion();
        $this->assertIsArray($versions);
        $this->assertNotEmpty($versions);
    }

    public function testSetAndGet(): void
    {
        $this->assertTrue(
            $this->mc->set('mc:greeting', 'Hello from valkey-glide-php!')
        );
        $this->assertEquals(
            'Hello from valkey-glide-php!',
            $this->mc->get('mc:greeting')
        );
    }

    public function testDelete(): void
    {
        $this->mc->set('mc:greeting', 'temp');
        $this->assertTrue($this->mc->delete('mc:greeting'));
        $this->assertFalse($this->mc->get('mc:greeting'));
        $this->assertEquals(Memcached::RES_NOTFOUND, $this->mc->getResultCode());
    }

    public function testIncrement(): void
    {
        $this->mc->set('mc:counter', 1);
        $this->assertEquals(2, $this->mc->increment('mc:counter'));
        $this->assertEquals(4, $this->mc->increment('mc:counter', 2));
    }
}
