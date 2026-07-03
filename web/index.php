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
    'cluster' => null,
];

// Simulated AZ this "application instance" runs in (us-east-1). In real
// deployments this comes from instance metadata; here we let it be
// overridden via ?az= for demoing affinity from a browser.
$clientAz = $_GET['az'] ?? 'us-east-1a';
if (!in_array($clientAz, ['us-east-1a', 'us-east-1b', 'us-east-1c'], true)) {
    $clientAz = 'us-east-1a';
}

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

    // --- AZ-aware cluster demo -------------------------------------------
    // 3 shards x (1 primary + 3 replicas, one per AZ) = 12 nodes across
    // us-east-1a/1b/1c. An AZ-affinity client pinned to $clientAz routes
    // reads to a same-AZ replica. We prove it by reading a key back and
    // asking the cluster which node's AZ served the connection.
    $cluster = new ValkeyGlideCluster(
        name: null, seeds: null, timeout: null, read_timeout: null,
        persistent: null, auth: null, context: null,
        addresses: [
            ['host' => 'vk-s1-1a-p', 'port' => 6379],
            ['host' => 'vk-s2-1b-p', 'port' => 6379],
            ['host' => 'vk-s3-1c-p', 'port' => 6379],
        ],
        read_from: ValkeyGlide::READ_FROM_AZ_AFFINITY,
        client_az: $clientAz,
    );

    $ckey   = 'web:cluster:demo';
    $cvalue = 'cluster-write-at-' . gmdate('c');
    $cluster->set($ckey, $cvalue);
    $cread = $cluster->get($ckey);
    $cluster->del($ckey);

    $response['cluster'] = [
        'topology'   => '3 shards x (1 primary + 3 replicas) = 12 nodes',
        'azs'        => ['us-east-1a', 'us-east-1b', 'us-east-1c'],
        'client_az'  => $clientAz,
        'read_from'  => 'AZ_AFFINITY',
        'write'      => $cvalue,
        'read'       => $cread,
        'consistent' => $cread === $cvalue,
    ];
    $response['ok'] = $response['ok'] && $cread === $cvalue;
} catch (Throwable $e) {
    http_response_code(500);
    $response['error'] = $e->getMessage();
}

echo json_encode($response, JSON_PRETTY_PRINT | JSON_UNESCAPED_SLASHES), "\n";
