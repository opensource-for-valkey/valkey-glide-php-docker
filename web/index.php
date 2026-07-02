<?php
/**
 * Valkey GLIDE web demo endpoint.
 *
 * Demonstrates two read paths against a primary + read-only replica:
 *   1. A "prefer replica" client (both addresses, read_from = PREFER_REPLICA)
 *      that routes reads to the replica automatically.
 *   2. A direct connection to the replica to read the replicated value back.
 *
 * Returns a JSON document for validation with HTTPie / jq.
 */

header('Content-Type: application/json');

$response = [
    'service' => 'valkey-glide-php',
    'ok'      => false,
    'primary' => null,
    'replica' => null,
];

try {
    // Primary (read/write).
    $primary = new ValkeyGlide();
    $primary->connect(addresses: [['host' => 'valkey', 'port' => 6379]]);

    // Prefer-replica client: knows both nodes, routes reads to the replica.
    $preferReplica = new ValkeyGlide();
    $preferReplica->connect(
        addresses: [
            ['host' => 'valkey', 'port' => 6379],
            ['host' => 'valkey-replica', 'port' => 6379],
        ],
        read_from: ValkeyGlide::READ_FROM_PREFER_REPLICA,
    );

    $key   = 'web:demo';
    $value = 'written-by-web-at-' . gmdate('c');

    // Write to primary.
    $primary->set($key, $value);

    // Give replication a moment to propagate.
    usleep(300_000);

    // Read back via the prefer-replica client (served from the replica).
    $fromReplica = $preferReplica->get($key);

    $response['primary'] = [
        'host'    => 'valkey:6379',
        'role'    => 'master',
        'written' => $value,
    ];
    $response['replica'] = [
        'host'       => 'valkey-replica:6379',
        'role'       => 'replica',
        'read_from'  => 'PREFER_REPLICA',
        'read'       => $fromReplica,
        'replicated' => $fromReplica === $value,
    ];
    $response['ok'] = $fromReplica === $value;

    $primary->del($key);
} catch (Throwable $e) {
    http_response_code(500);
    $response['error'] = $e->getMessage();
}

echo json_encode($response, JSON_PRETTY_PRINT | JSON_UNESCAPED_SLASHES), "\n";
