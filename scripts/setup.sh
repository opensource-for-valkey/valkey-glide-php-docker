#!/usr/bin/env bash
#
# setup.sh — build and start the Valkey GLIDE PHP stack with gum.
#
# Brings up nginx, php-fpm, mariadb, the standalone Valkey primary and its
# read-only replica, then installs PHPUnit inside the PHP container.

set -euo pipefail

cd "$(dirname "$0")/.."

PHP_CONTAINER="valkey-glide-php-docker-php-1"

require() {
    command -v "$1" >/dev/null 2>&1 || {
        echo "Missing required tool: $1" >&2
        exit 1
    }
}

require gum
require docker

gum style --border double --margin "1" --padding "1 2" --border-foreground 212 \
    "Valkey GLIDE PHP — Setup"

gum spin --spinner dot --title "Building images..." -- \
    docker compose build

gum spin --spinner dot --title "Starting containers..." -- \
    docker compose up -d

gum spin --spinner dot --title "Waiting for primary..." -- \
    bash -c 'until docker compose exec -T valkey valkey-cli ping >/dev/null 2>&1; do sleep 1; done'

gum spin --spinner dot --title "Waiting for replica link..." -- \
    bash -c 'until docker compose exec -T valkey-replica valkey-cli info replication 2>/dev/null | grep -q "master_link_status:up"; do sleep 1; done'

gum spin --spinner dot --title "Installing PHPUnit in PHP container..." -- \
    docker exec "$PHP_CONTAINER" sh -c "cd /var/www/cli/ && composer install --no-interaction || composer require --dev phpunit/phpunit --no-interaction"

gum style --foreground 42 "Stack is up."
echo
gum format -- "- Web endpoint: **http://localhost:8080**"
gum format -- "- Primary:      **localhost:6379**"
gum format -- "- Replica:      **localhost:6380** (read-only)"
echo
docker compose ps
