<?php
/**
 * PHPUnit tests for PHP -> SQLite connectivity via PDO (pdo_sqlite).
 *
 * SQLite is file-based: connects to the database file created and seeded
 * by scripts/setup.sh (default path matches SQLITE_DATABASE in .env).
 * Verifies the connection, a basic query, and read/write against the
 * seeded cache_entries table.
 */

require_once __DIR__ . '/DatabaseTestBase.php';

class SqliteConnectionTest extends DatabaseTestBase
{
    protected function getDriver(): string
    {
        return 'sqlite';
    }

    protected function getPdo(): PDO
    {
        $path = getenv('SQLITE_DATABASE') ?: '/var/www/sqlite/valkeyglide.sqlite';

        return new PDO("sqlite:{$path}");
    }
}
