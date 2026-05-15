<?php
/**
 * Base test class for Valkey GLIDE operations
 *
 * Contains all test methods. Child classes provide setup/teardown for specific configurations.
 */

use PHPUnit\Framework\TestCase;

abstract class ValkeyTestBase extends TestCase
{
    protected $client;

    // Ping Test
    public function testPing(): void
    {
        $result = $this->client->ping();
        $this->assertTrue($result);
    }

    // String Operations Tests
    public function testSetAndGet(): void
    {
        $this->client->set('greeting', 'Hello from Valkey GLIDE PHP!');
        $value = $this->client->get('greeting');
        $this->assertEquals('Hello from Valkey GLIDE PHP!', $value);
    }

    public function testSetex(): void
    {
        $this->client->setex('session:abc123', 60, 'user_data_here');
        $ttl = $this->client->ttl('session:abc123');
        $this->assertGreaterThan(0, $ttl);
        $this->assertLessThanOrEqual(60, $ttl);
    }

    public function testIncrDecr(): void
    {
        $this->client->set('counter', '0');
        $this->client->incr('counter');
        $this->client->incr('counter');
        $this->client->incr('counter');
        $this->client->decr('counter');
        $counterVal = $this->client->get('counter');
        $this->assertEquals('2', $counterVal);
    }

    public function testMsetMget(): void
    {
        $this->client->mset([
            'color:red' => '#FF0000',
            'color:green' => '#00FF00',
            'color:blue' => '#0000FF',
        ]);
        $colors = $this->client->mget(['color:red', 'color:green', 'color:blue']);
        $this->assertEquals(['#FF0000', '#00FF00', '#0000FF'], $colors);
    }

    // Hash Operations Tests
    public function testHsetHget(): void
    {
        $this->client->hset('user:1', 'name', 'Alice');
        $name = $this->client->hget('user:1', 'name');
        $this->assertEquals('Alice', $name);
    }

    public function testHgetall(): void
    {
        $this->client->hset('user:1', 'name', 'Alice');
        $this->client->hset('user:1', 'email', 'alice@example.com');
        $this->client->hset('user:1', 'role', 'admin');

        $allFields = $this->client->hgetall('user:1');
        $this->assertIsArray($allFields);
        $this->assertEquals('Alice', $allFields['name']);
        $this->assertEquals('alice@example.com', $allFields['email']);
        $this->assertEquals('admin', $allFields['role']);
    }

    // List Operations Tests
    public function testRpushLlen(): void
    {
        $this->client->rpush('task_queue', ['send_email', 'process_payment', 'generate_report']);
        $length = $this->client->llen('task_queue');
        $this->assertEquals(3, $length);
    }

    public function testLrange(): void
    {
        $this->client->rpush('task_queue', ['send_email', 'process_payment', 'generate_report']);
        $allTasks = $this->client->lrange('task_queue', 0, -1);
        $this->assertEquals(['send_email', 'process_payment', 'generate_report'], $allTasks);
    }

    public function testLpop(): void
    {
        $this->client->rpush('task_queue', ['send_email', 'process_payment', 'generate_report']);
        $nextTask = $this->client->lpop('task_queue');
        $this->assertEquals('send_email', $nextTask);
        $this->assertEquals(2, $this->client->llen('task_queue'));
    }

    // Set Operations Tests
    public function testSaddScard(): void
    {
        $this->client->sadd('online_users', 'alice');
        $this->client->sadd('online_users', 'bob');
        $this->client->sadd('online_users', 'charlie');
        $this->client->sadd('online_users', 'diana');
        $count = $this->client->scard('online_users');
        $this->assertEquals(4, $count);
    }

    public function testSismember(): void
    {
        $this->client->sadd('online_users', 'alice');
        $this->client->sadd('online_users', 'bob');
        $isMember = $this->client->sismember('online_users', 'bob');
        $this->assertTrue($isMember);
        $notMember = $this->client->sismember('online_users', 'eve');
        $this->assertFalse($notMember);
    }

    public function testSmembers(): void
    {
        $this->client->sadd('online_users', 'alice');
        $this->client->sadd('online_users', 'bob');
        $members = $this->client->smembers('online_users');
        $this->assertIsArray($members);
        $this->assertCount(2, $members);
        $this->assertContains('alice', $members);
        $this->assertContains('bob', $members);
    }

    // Sorted Set Operations Tests
    public function testZaddZscore(): void
    {
        $this->client->zadd('leaderboard', 100, 'alice');
        $this->client->zadd('leaderboard', 250, 'bob');
        $this->client->zadd('leaderboard', 175, 'charlie');

        $bobScore = $this->client->zscore('leaderboard', 'bob');
        $this->assertEquals(250, $bobScore);
    }

    public function testZrangeReversed(): void
    {
        $this->client->zadd('leaderboard', 100, 'alice');
        $this->client->zadd('leaderboard', 250, 'bob');
        $this->client->zadd('leaderboard', 175, 'charlie');

        $topPlayers = $this->client->zrange('leaderboard', 0, -1, ['REV' => true]);
        $this->assertEquals(['bob', 'charlie', 'alice'], $topPlayers);
    }

    // Key Management Tests
    public function testExists(): void
    {
        $this->client->set('greeting', 'hello');
        $exists = $this->client->exists('greeting');
        $this->assertEquals(1, $exists);

        $notExists = $this->client->exists('nonexistent');
        $this->assertEquals(0, $notExists);
    }

    public function testExpireTtl(): void
    {
        $this->client->set('greeting', 'hello');
        $this->client->expire('greeting', 300);
        $ttl = $this->client->ttl('greeting');
        $this->assertGreaterThan(0, $ttl);
        $this->assertLessThanOrEqual(300, $ttl);
    }

    public function testType(): void
    {
        $this->client->hset('user:1', 'name', 'Alice');
        $type = $this->client->type('user:1');
        $this->assertIsInt($type);
    }
}
