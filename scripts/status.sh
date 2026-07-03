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

# --- Cluster topology -----------------------------------------------------
cluster_state=$(docker compose exec -T vk-s1-1a-p valkey-cli cluster info 2>/dev/null | grep cluster_state | tr -d '\r' | cut -d: -f2)
gum style --bold --foreground 39 "Cluster topology (state: ${cluster_state:-unknown}):"

# Build IP→service-name map (cluster nodes report IPs, not hostnames).
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

# Capture cluster nodes output once (avoid stdin issues in loops).
cluster_nodes=$(docker compose exec -T vk-s1-1a-p valkey-cli cluster nodes 2>/dev/null)

# Build id→slots map from primary nodes (replicas inherit their primary's slots).
primary_slots=""
while IFS=' ' read -r nid endpoint flags _master _ping _pong _epoch _link slots; do
    if echo "$flags" | grep -q "master"; then
        primary_slots="${primary_slots}${nid} ${slots}"$'\n'
    fi
done <<< "$cluster_nodes"

lookup_slots() {
    echo "$primary_slots" | grep "^$1 " | cut -d' ' -f2-
}

{
    printf "NODE\tROLE\tAZ\tSLOTS\n"
    while IFS=' ' read -r _id endpoint flags master _ping _pong _epoch _link slots; do
        ip="${endpoint%%:*}"
        host=$(resolve_host "$ip")
        if echo "$flags" | grep -q "master"; then
            role="primary"
            slot_range="$slots"
        else
            role="replica"
            slot_range=$(lookup_slots "$master")
        fi
        az=$(docker compose exec -T "$host" valkey-cli config get availability-zone </dev/null 2>/dev/null | tail -1 | tr -d '\r')
        printf "%s\t%s\t%s\t%s\n" "$host" "$role" "$az" "$slot_range"
    done <<< "$cluster_nodes" | sort -t$'\t' -k2,2 -k3,3
} | gum table --print --separator $'\t' --border.foreground 212
