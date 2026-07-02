#!/usr/bin/env bash
#
# teardown.sh — stop and remove the Valkey GLIDE PHP stack with gum.

set -euo pipefail

cd "$(dirname "$0")/.."

command -v gum >/dev/null 2>&1 || { echo "Missing required tool: gum" >&2; exit 1; }

gum style --border double --margin "1" --padding "1 2" --border-foreground 212 \
    "Valkey GLIDE PHP — Teardown"

REMOVE_VOLUMES="no"
if gum confirm "Also remove volumes (MariaDB data)?"; then
    REMOVE_VOLUMES="yes"
fi

if [ "$REMOVE_VOLUMES" = "yes" ]; then
    gum spin --spinner dot --title "Stopping and removing containers + volumes..." -- \
        docker compose down -v
else
    gum spin --spinner dot --title "Stopping and removing containers..." -- \
        docker compose down
fi

gum style --foreground 42 "Stack is down."
