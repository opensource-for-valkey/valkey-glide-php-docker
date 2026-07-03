#!/usr/bin/env bash
#
# teardown.sh — stop and remove the Valkey GLIDE PHP stack with gum.
#
# Stops the containers and optionally deletes the persisted database data,
# which lives in bind-mounted host directories (./mariadb, ./postgres,
# ./sqlite) rather than Docker named volumes.

set -euo pipefail

cd "$(dirname "$0")/.."

command -v gum >/dev/null 2>&1 || { echo "Missing required tool: gum" >&2; exit 1; }

# Bind-mounted data directories (see docker-compose.yml).
DATA_DIRS=(mariadb postgres)
SQLITE_DB="sqlite/valkeyglide.sqlite"

gum style --border double --margin "1" --padding "1 2" --border-foreground 212 \
    "Valkey GLIDE PHP — Teardown"

gum spin --spinner dot --title "Stopping and removing containers..." -- \
    docker compose down

# DB data is bind-mounted on the host; offer to delete it explicitly.
if gum confirm "Also delete persisted database data (${DATA_DIRS[*]}, ${SQLITE_DB})?"; then
    for dir in "${DATA_DIRS[@]}"; do
        [ -d "$dir" ] && rm -rf "$dir" && gum style --foreground 244 "Removed ./${dir}"
    done
    [ -f "$SQLITE_DB" ] && rm -f "$SQLITE_DB" && gum style --foreground 244 "Removed ./${SQLITE_DB}"
fi

gum style --foreground 42 "Stack is down."
