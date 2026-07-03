#!/bin/sh
#
# cluster-init-tls.sh — form the TLS-enabled AZ-aware Valkey cluster (one-shot).
#
# Same idea as cluster-init.sh, but every valkey-cli call speaks TLS
# (--tls --cacert /etc/certs/ca.crt) because the nodes listen only on the
# TLS port. This cluster is intentionally smaller: 3 shards, each with
# 1 primary + 1 replica (6 nodes total). The replica sits in a DIFFERENT
# AZ from its primary — the realistic Multi-AZ failover pattern:
#
#   Shard 1  primary=us-east-1a  replica=us-east-1b
#   Shard 2  primary=us-east-1b  replica=us-east-1c
#   Shard 3  primary=us-east-1c  replica=us-east-1a
#
# valkey-cli's --cluster-replicas cannot control AZ placement, so we create
# the cluster from the 3 primaries only and then attach each replica to a
# specific primary with `add-node --cluster-slave --cluster-master-id`.

set -eu

PORT=6379

# valkey-cli TLS flags. --tls-auth-clients is "no" on the server side, so no
# client cert is required — only the CA to verify the server.
TLS="--tls --cacert /etc/certs/ca.crt"

# Shard primaries (one per AZ), space-separated.
PRIMARIES="vk-tls-s1-1a-p vk-tls-s2-1b-p vk-tls-s3-1c-p"

# Each replica mapped to its shard's primary: "<replica>=<primary>".
REPLICAS="
vk-tls-s1-1b-r=vk-tls-s1-1a-p
vk-tls-s2-1c-r=vk-tls-s2-1b-p
vk-tls-s3-1a-r=vk-tls-s3-1c-p
"

ALL_NODES="$PRIMARIES $(echo "$REPLICAS" | sed 's/=.*//' | tr '\n' ' ')"

log() { echo "[cluster-init-tls] $*"; }

# Block until a node answers PING over TLS.
wait_for() {
    node="$1"
    # shellcheck disable=SC2086
    until valkey-cli $TLS -h "$node" -p "$PORT" ping >/dev/null 2>&1; do
        sleep 1
    done
}

log "Waiting for all 6 TLS nodes to accept connections..."
for node in $ALL_NODES; do
    wait_for "$node"
    log "  up: $node"
done

# If the cluster is already formed (e.g. a re-run), do nothing.
# shellcheck disable=SC2086
STATE=$(valkey-cli $TLS -h vk-tls-s1-1a-p -p "$PORT" cluster info 2>/dev/null | tr -d '\r' | awk -F: '/cluster_state/{print $2}')
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
valkey-cli $TLS --cluster create $CREATE_ADDRS --cluster-replicas 0 --cluster-yes

# Wait for the freshly created cluster to converge before adding replicas.
log "Waiting for cluster_state:ok..."
# shellcheck disable=SC2086
until [ "$(valkey-cli $TLS -h vk-tls-s1-1a-p -p "$PORT" cluster info 2>/dev/null | tr -d '\r' | awk -F: '/cluster_state/{print $2}')" = "ok" ]; do
    sleep 1
done

# 2) Attach each replica to its shard's primary by node-id.
echo "$REPLICAS" | while IFS='=' read -r replica primary; do
    [ -z "$replica" ] && continue
    # shellcheck disable=SC2086
    master_id=$(valkey-cli $TLS -h "$primary" -p "$PORT" cluster myid | tr -d '\r')
    log "Attaching $replica -> $primary (master-id $master_id)"
    # shellcheck disable=SC2086
    valkey-cli $TLS --cluster add-node "${replica}:${PORT}" "${primary}:${PORT}" \
        --cluster-slave --cluster-master-id "$master_id"
done

log "Waiting for all replicas to sync..."
# Expect 3 masters + 3 slaves = 6 known nodes; wait for 3 slaves.
# shellcheck disable=SC2086
until [ "$(valkey-cli $TLS -h vk-tls-s1-1a-p -p "$PORT" cluster nodes 2>/dev/null | grep -c slave)" -eq 3 ]; do
    sleep 1
done

log "Cluster ready:"
# shellcheck disable=SC2086
valkey-cli $TLS -h vk-tls-s1-1a-p -p "$PORT" cluster nodes | tr -d '\r' | \
    awk '{printf "  %-20s %s\n", $2, $3}'

log "Done."
