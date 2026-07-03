#!/bin/sh
#
# cluster-init.sh — form the AZ-aware Valkey cluster (one-shot).
#
# Simulates ElastiCache/MemoryDB running in us-east-1 across 3 AZs. The
# topology is 3 shards, each with 1 primary + 3 replicas (one replica per
# AZ, including the primary's own AZ) = 12 nodes. Because every AZ holds a
# node for every shard, an AZ-affinity client (READ_FROM_AZ_AFFINITY +
# client_az) can always serve reads from a node in its own AZ.
#
#   Shard 1  primary=us-east-1a  replicas: 1a, 1b, 1c
#   Shard 2  primary=us-east-1b  replicas: 1a, 1b, 1c
#   Shard 3  primary=us-east-1c  replicas: 1a, 1b, 1c
#
# valkey-cli's --cluster-replicas cannot control AZ placement, so we create
# the cluster from the 3 primaries only and then attach each replica to a
# specific primary with `add-node --cluster-slave --cluster-master-id`.

set -eu

PORT=6379

# Shard primaries (one per AZ), space-separated.
PRIMARIES="vk-s1-1a-p vk-s2-1b-p vk-s3-1c-p"

# Each replica mapped to its shard's primary: "<replica>=<primary>".
REPLICAS="
vk-s1-1a-r=vk-s1-1a-p
vk-s1-1b-r=vk-s1-1a-p
vk-s1-1c-r=vk-s1-1a-p
vk-s2-1a-r=vk-s2-1b-p
vk-s2-1b-r=vk-s2-1b-p
vk-s2-1c-r=vk-s2-1b-p
vk-s3-1a-r=vk-s3-1c-p
vk-s3-1b-r=vk-s3-1c-p
vk-s3-1c-r=vk-s3-1c-p
"

ALL_NODES="$PRIMARIES $(echo "$REPLICAS" | sed 's/=.*//' | tr '\n' ' ')"

log() { echo "[cluster-init] $*"; }

# Block until a node answers PING.
wait_for() {
    node="$1"
    until valkey-cli -h "$node" -p "$PORT" ping >/dev/null 2>&1; do
        sleep 1
    done
}

log "Waiting for all 12 nodes to accept connections..."
for node in $ALL_NODES; do
    wait_for "$node"
    log "  up: $node"
done

# If the cluster is already formed (e.g. a re-run), do nothing.
STATE=$(valkey-cli -h vk-s1-1a-p -p "$PORT" cluster info 2>/dev/null | tr -d '\r' | awk -F: '/cluster_state/{print $2}')
if [ "$STATE" = "ok" ]; then
    log "Cluster already formed (cluster_state:ok) — nothing to do."
    exit 0
fi

# 1) Create the cluster from the primaries only (all 16384 slots, no replicas).
log "Creating cluster from primaries: $PRIMARIES"
CREATE_ADDRS=""
for p in $PRIMARIES; do
    CREATE_ADDRS="$CREATE_ADDRS ${p}:${PORT}"
done
# shellcheck disable=SC2086
valkey-cli --cluster create $CREATE_ADDRS --cluster-replicas 0 --cluster-yes

# Wait for the freshly created cluster to converge before adding replicas.
log "Waiting for cluster_state:ok..."
until [ "$(valkey-cli -h vk-s1-1a-p -p "$PORT" cluster info 2>/dev/null | tr -d '\r' | awk -F: '/cluster_state/{print $2}')" = "ok" ]; do
    sleep 1
done

# 2) Attach each replica to its shard's primary by node-id.
echo "$REPLICAS" | while IFS='=' read -r replica primary; do
    [ -z "$replica" ] && continue
    master_id=$(valkey-cli -h "$primary" -p "$PORT" cluster myid | tr -d '\r')
    log "Attaching $replica -> $primary (master-id $master_id)"
    valkey-cli --cluster add-node "${replica}:${PORT}" "${primary}:${PORT}" \
        --cluster-slave --cluster-master-id "$master_id"
done

log "Waiting for all replicas to sync..."
# Expect 3 masters + 9 slaves = 12 known nodes with cluster_state:ok.
until [ "$(valkey-cli -h vk-s1-1a-p -p "$PORT" cluster nodes 2>/dev/null | grep -c slave)" -eq 9 ]; do
    sleep 1
done

log "Cluster ready:"
valkey-cli -h vk-s1-1a-p -p "$PORT" cluster nodes | tr -d '\r' | \
    awk '{printf "  %-20s %s\n", $2, $3}'

log "Done."
