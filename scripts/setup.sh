#!/usr/bin/env bash
#
# setup.sh — build and start the Valkey GLIDE PHP stack with gum.
#
# Brings up OpenResty, php-fpm, MariaDB, PostgreSQL, Memcached, the
# standalone Valkey primary and its read-only replica, then installs
# PHPUnit inside the PHP container and prints connection hints.

set -euo pipefail

cd "$(dirname "$0")/.."

PHP_CONTAINER="valkey-glide-php-docker-php-1"

# Load credentials from .env (fall back to the documented defaults).
[ -f .env ] && set -a && . ./.env && set +a
DB=${MARIADB_DATABASE:-valkeyglide}
DB_USER=${MARIADB_USER:-valkeyglide}
DB_PASS=${MARIADB_PASSWORD:-valkeyglide_secret}
PG_DB=${POSTGRES_DB:-valkeyglide}
PG_USER=${POSTGRES_USER:-valkeyglide}
PG_PASS=${POSTGRES_PASSWORD:-valkeyglide_secret}

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

# SQLite is file-based; create and seed the database file if missing.
gum spin --spinner dot --title "Seeding SQLite database..." -- \
    docker exec "$PHP_CONTAINER" sh -c "test -f /var/www/sqlite/valkeyglide.sqlite || sqlite3 /var/www/sqlite/valkeyglide.sqlite < /var/www/databases-sqlite.sql"

gum style --foreground 42 "Stack is up."
echo
gum format -- "- Web endpoint: **http://localhost:8080**"
gum format -- "- Primary:      **localhost:6379**"
gum format -- "- Replica:      **localhost:6380** (read-only)"
echo

# --- Connection hints -------------------------------------------------
gum style --border rounded --padding "0 1" --border-foreground 39 \
    "How to connect (install the CLI tools on your host if needed)"

gum format <<EOF

**MariaDB** — \`mycli\` (pip install mycli) or the bundled client:
  mycli -h 127.0.0.1 -P 3306 -u ${DB_USER} -p${DB_PASS} ${DB}
  docker compose exec mariadb mariadb -u ${DB_USER} -p${DB_PASS} ${DB}

**PostgreSQL** — \`pgcli\` (pip install pgcli) or the bundled client:
  PGPASSWORD=${PG_PASS} pgcli -h 127.0.0.1 -p 5432 -U ${PG_USER} ${PG_DB}
  docker compose exec postgres psql -U ${PG_USER} -d ${PG_DB}

**SQLite** — \`litecli\` (pip install litecli) or sqlite3:
  litecli sqlite/valkeyglide.sqlite
  docker compose exec php sqlite3 /var/www/sqlite/valkeyglide.sqlite

**Valkey (primary)** — valkey-cli (redis-cli also works):
  valkey-cli -h 127.0.0.1 -p 6379
  docker compose exec valkey valkey-cli

**Valkey (replica, read-only)** — port 6380:
  valkey-cli -h 127.0.0.1 -p 6380
  docker compose exec valkey-replica valkey-cli

**Memcached** — no REPL; use libmemcached-tools or nc:
  memcstat --servers=127.0.0.1:11211
  printf 'stats\r\nquit\r\n' | nc 127.0.0.1 11211
EOF

echo
docker compose ps
