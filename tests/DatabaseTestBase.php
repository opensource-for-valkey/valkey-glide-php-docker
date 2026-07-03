<?php
/**
 * Base test class for PDO database connectivity.
 *
 * Contains the shared assertions run against each database driver
 * (MariaDB, PostgreSQL). Child classes provide the PDO connection and
 * the driver name via getPdo() / getDriver().
 */

use PHPUnit\Framework\TestCase;

abstract class DatabaseTestBase extends TestCase
{
    protected PDO $pdo;

    /** Build a PDO connection for the concrete driver. */
    abstract protected function getPdo(): PDO;

    /** Expected PDO driver name (e.g. 'mysql', 'pgsql'). */
    abstract protected function getDriver(): string;

    protected function setUp(): void
    {
        $this->pdo = $this->getPdo();
        $this->pdo->setAttribute(PDO::ATTR_ERRMODE, PDO::ERRMODE_EXCEPTION);
    }

    public function testConnectionIsEstablished(): void
    {
        $this->assertInstanceOf(PDO::class, $this->pdo);
        $this->assertEquals(
            $this->getDriver(),
            $this->pdo->getAttribute(PDO::ATTR_DRIVER_NAME)
        );
    }

    public function testSelectOne(): void
    {
        $value = $this->pdo->query('SELECT 1')->fetchColumn();
        $this->assertEquals(1, $value);
    }

    public function testServerVersionIsReadable(): void
    {
        $version = $this->pdo->getAttribute(PDO::ATTR_SERVER_VERSION);
        $this->assertNotEmpty($version);
    }

    public function testSeededCacheEntryExists(): void
    {
        $stmt = $this->pdo->prepare(
            'SELECT value FROM cache_entries WHERE key_name = ?'
        );
        $stmt->execute(['greeting']);
        $value = $stmt->fetchColumn();
        $this->assertEquals('Hello from valkey-glide-php!', $value);
    }

    public function testInsertAndReadBack(): void
    {
        $key = 'test:connectivity';
        $this->pdo->prepare('DELETE FROM cache_entries WHERE key_name = ?')
            ->execute([$key]);

        $this->pdo->prepare(
            'INSERT INTO cache_entries (key_name, value) VALUES (?, ?)'
        )->execute([$key, 'roundtrip']);

        $stmt = $this->pdo->prepare(
            'SELECT value FROM cache_entries WHERE key_name = ?'
        );
        $stmt->execute([$key]);
        $this->assertEquals('roundtrip', $stmt->fetchColumn());

        // Cleanup
        $this->pdo->prepare('DELETE FROM cache_entries WHERE key_name = ?')
            ->execute([$key]);
    }
}
