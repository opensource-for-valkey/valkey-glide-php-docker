#!/usr/bin/env bash
#
# status.sh — display running services and Valkey cluster topology.

set -euo pipefail

cd "$(dirname "$0")/.."

command -v gum >/dev/null 2>&1 || { echo "Missing required tool: gum" >&2; exit 1; }

gum style --border double --margin "1" --padding "1 2" --border-foreground 212 \
    "Valkey GLIDE PHP — Status"

# --- Docker services ------------------------------------------------------
gum style --bold --foreground 39 "Docker services:"
{
    printf "SERVICE\tIMAGE\tSTATUS\tPORTS\n"
    docker compose ps --format json 2>/dev/null | jq -r '
        [.Service, .Image, .State, (.Ports // "" | gsub("->"; "→"))] | @tsv
    ' | sort -t$'\t' -k1,1
} | gum table --print --separator $'\t' --border.foreground 212

echo

# --- Standalone Valkey health ---------------------------------------------
gum style --bold --foreground 39 "Standalone Valkey:"
primary_ok=$(docker compose exec -T valkey valkey-cli ping 2>/dev/null | tr -d '\r')
replica_link=$(docker compose exec -T valkey-replica valkey-cli info replication 2>/dev/null | grep master_link_status | tr -d '\r' | cut -d: -f2)
{
    printf "NODE\tROLE\tSTATUS\n"
    printf "valkey\tprimary\t%s\n" "${primary_ok:-down}"
    printf "valkey-replica\treplica\tlink ${replica_link:-down}\n"
} | gum table --print --separator $'\t' --border.foreground 212

echo

# --- Standalone Valkey over TLS (tls profile) -----------------------------
tls_flags="--tls --cacert /etc/certs/ca.crt"
tls_primary_ok=$(docker compose exec -T valkey-tls valkey-cli $tls_flags ping 2>/dev/null | tr -d '\r')
if [ -n "$tls_primary_ok" ]; then
    tls_replica_link=$(docker compose exec -T valkey-tls-replica valkey-cli $tls_flags info replication 2>/dev/null | grep master_link_status | tr -d '\r' | cut -d: -f2)
    gum style --bold --foreground 39 "Standalone Valkey (TLS):"
    {
        printf "NODE\tROLE\tSTATUS\n"
        printf "valkey-tls\tprimary\t%s\n" "${tls_primary_ok:-down}"
        printf "valkey-tls-replica\treplica\tlink ${tls_replica_link:-down}\n"
    } | gum table --print --separator $'\t' --border.foreground 212
    echo
fi

# --- Cluster topology -----------------------------------------------------

# Build IP→service-name map once (cluster nodes report IPs, not hostnames).
ip_map=$(docker network inspect valkey-glide-php-docker_valkey-net \
    -f '{{range .Containers}}{{.IPv4Address}} {{.Name}}{{"\n"}}{{end}}' 2>/dev/null | grep vk-)

resolve_host() {
    local ip="$1"
    local match
    match=$(echo "$ip_map" | grep "^${ip}/" | awk '{print $2}')
    match="${match#valkey-glide-php-docker-}"
    match="${match%-1}"
    echo "${match:-$ip}"
}

# render_topology <title> <seed-node> <cli-flags>
# Prints a bold title + gum table for the cluster reachable via <seed-node>.
# <cli-flags> is passed to every valkey-cli call (empty for plaintext, the
# TLS flags for the encrypted cluster). No-op if the seed node isn't running.
render_topology() {
    local title="$1" seed="$2" flags="$3"

    local state
    state=$(docker compose exec -T "$seed" valkey-cli $flags cluster info 2>/dev/null | grep cluster_state | tr -d '\r' | cut -d: -f2)
    [ -z "$state" ] && return 0   # seed not up (e.g. tls profile not started)

    gum style --bold --foreground 39 "${title} (state: ${state:-unknown}):"

    # Capture cluster nodes output once (avoid stdin issues in loops).
    local cluster_nodes
    cluster_nodes=$(docker compose exec -T "$seed" valkey-cli $flags cluster nodes 2>/dev/null)

    # id→slots map from primaries (replicas inherit their primary's slots).
    local primary_slots=""
    local nid endpoint flg master slots
    while IFS=' ' read -r nid endpoint flg master _ping _pong _epoch _link slots; do
        if echo "$flg" | grep -q "master"; then
            primary_slots="${primary_slots}${nid} ${slots}"$'\n'
        fi
    done <<< "$cluster_nodes"

    {
        printf "NODE\tROLE\tAZ\tSLOTS\n"
        while IFS=' ' read -r _id endpoint flg master _ping _pong _epoch _link slots; do
            local ip host role slot_range az
            ip="${endpoint%%:*}"
            host=$(resolve_host "$ip")
            if echo "$flg" | grep -q "master"; then
                role="primary"
                slot_range="$slots"
            else
                role="replica"
                slot_range=$(echo "$primary_slots" | grep "^$master " | cut -d' ' -f2-)
            fi
            az=$(docker compose exec -T "$host" valkey-cli $flags config get availability-zone </dev/null 2>/dev/null | tail -1 | tr -d '\r')
            printf "%s\t%s\t%s\t%s\n" "$host" "$role" "$az" "$slot_range"
        done <<< "$cluster_nodes" | sort -t$'\t' -k2,2 -k3,3
    } | gum table --print --separator $'\t' --border.foreground 212
}

render_topology "Cluster topology" vk-s1-1a-p ""

echo

render_topology "TLS cluster topology" vk-tls-s1-1a-p "--tls --cacert /etc/certs/ca.crt"
