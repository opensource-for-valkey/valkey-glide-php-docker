<?php
/**
 * PHPUnit tests for PHP -> PostgreSQL connectivity via PDO (pdo_pgsql).
 *
 * Connects to the postgres service using the POSTGRES_* credentials
 * (defaults match .env). Verifies the connection, a basic query, and
 * read/write against the seeded cache_entries table.
 */

require_once __DIR__ . '/DatabaseTestBase.php';

class PostgresConnectionTest extends DatabaseTestBase
{
    protected function getDriver(): string
    {
        return 'pgsql';
    }

    protected function getPdo(): PDO
    {
        $host = getenv('POSTGRES_HOST') ?: 'postgres';
        $db   = getenv('POSTGRES_DB') ?: 'valkeyglide';
        $user = getenv('POSTGRES_USER') ?: 'valkeyglide';
        $pass = getenv('POSTGRES_PASSWORD') ?: 'valkeyglide_secret';

        return new PDO("pgsql:host={$host};dbname={$db}", $user, $pass);
    }
}
