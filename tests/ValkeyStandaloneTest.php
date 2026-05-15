<?php
/**
 * PHPUnit tests for Valkey GLIDE standalone connection
 *
 * Extends ValkeyTestBase with standalone-specific setup/teardown
 */

require_once __DIR__ . '/ValkeyTestBase.php';

class ValkeyStandaloneTest extends ValkeyTestBase
{
    protected function setUp(): void
    {
        $this->client = new ValkeyGlide();
        $this->client->connect(
            addresses: [['host' => 'valkey', 'port' => 6379]]
        );
    }

    protected function tearDown(): void
    {
        // Cleanup test keys
        $keys = [
            'greeting', 'session:abc123', 'counter',
            'color:red', 'color:green', 'color:blue',
            'user:1', 'task_queue', 'online_users', 'leaderboard'
        ];
        foreach ($keys as $key) {
            $this->client->del($key);
        }
    }
}
