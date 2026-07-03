<?php
/**
 * PHPUnit tests for PHP -> MariaDB connectivity via PDO (pdo_mysql).
 *
 * Connects to the mariadb service using the MARIADB_* credentials
 * (defaults match .env). Verifies the connection, a basic query, and
 * read/write against the seeded cache_entries table.
 */

require_once __DIR__ . '/DatabaseTestBase.php';

class MariaDbConnectionTest extends DatabaseTestBase
{
    protected function getDriver(): string
    {
        return 'mysql';
    }

    protected function getPdo(): PDO
    {
        $host = getenv('MARIADB_HOST') ?: 'mariadb';
        $db   = getenv('MARIADB_DATABASE') ?: 'valkeyglide';
        $user = getenv('MARIADB_USER') ?: 'valkeyglide';
        $pass = getenv('MARIADB_PASSWORD') ?: 'valkeyglide_secret';

        return new PDO("mysql:host={$host};dbname={$db}", $user, $pass);
    }
}
