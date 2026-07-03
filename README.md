# Docker Valkey-Glide PHP

A Docker environment for developing with [valkey-glide-php](https://github.com/valkey-io/valkey-glide-php) — includes OpenResty (nginx + LuaJIT), PHP-FPM, and both standalone and cluster Valkey instances.

> The web server is [OpenResty](https://openresty.org/), configured from its own `openresty/` folder. The stock nginx image (`nginx.dockerfile` + `nginx/`) is kept for reference. To fall back to plain nginx, point the `openresty` service in `docker-compose.yml` at `nginx.dockerfile`.

## Prerequisites

- Docker & Docker Compose

## Quick Start

```bash
git clone https://github.com/opensource-for-valkey/valkey-glide-php-docker.git
cd valkey-glide-php-docker

# Build and start all services
docker compose up -d --build
```

## Scripts

Interactive helper scripts live in `scripts/` and use [gum](https://github.com/charmbracelet/gum). They require `gum`, `httpie`, `jq`, and `docker` on the host.

```bash
./scripts/setup.sh      # build + start the stack, install PHPUnit
./scripts/test.sh       # pick and run CLI + web-server tests
./scripts/test.sh --all # run every suite without prompting (CI-friendly)
./scripts/teardown.sh   # stop and remove the stack
```

`test.sh` runs these suites (choose any subset via gum; when stdin is not a TTY or `--all` is passed, all suites run automatically):

| Suite | What it checks |
|-------|----------------|
| Standalone (CLI) | PHPUnit against the standalone primary. |
| Replica (CLI) | PHPUnit — writes to primary, reads back from the replica via a `PREFER_REPLICA` client. |
| MariaDB (CLI) | PHPUnit — PHP → MariaDB connectivity via PDO (`pdo_mysql`). |
| PostgreSQL (CLI) | PHPUnit — PHP → PostgreSQL connectivity via PDO (`pdo_pgsql`). |
| SQLite (CLI) | PHPUnit — PHP → SQLite connectivity via PDO (`pdo_sqlite`). |
| Web server (HTTPie) | `GET http://localhost:8080/`, validates the JSON with HTTPie + `jq`. |

## Testing (manual)

Run CLI demos:
```bash
# SSH into the container if needed
docker exec -it valkey-glide-php-docker-php-1 bash

# Install PHPUnit in the PHP container
docker exec valkey-glide-php-docker-php-1 sh -c "cd /var/www/cli/ && composer require --dev phpunit/phpunit"

# Test standalone Valkey connection
docker exec valkey-glide-php-docker-php-1 /var/www/cli/vendor/bin/phpunit /var/www/cli/ValkeyStandaloneTest.php

# Test primary/replica replication
docker exec valkey-glide-php-docker-php-1 /var/www/cli/vendor/bin/phpunit /var/www/cli/ValkeyReplicaTest.php
```

Test the web endpoint:
```bash
http GET http://localhost:8080/
```

**Note:** Cluster configuration is still work in progress.

## Project Structure

| File | Description |
|------|-------------|
| `tests/ValkeyTestBase.php` | Abstract PHPUnit test class with all 18 test methods. |
| `tests/ValkeyStandaloneTest.php` | Standalone test implementation (extends ValkeyTestBase). |
| `tests/ValkeyReplicaTest.php` | Replication test — writes to primary, reads from replica. |
| `tests/DatabaseTestBase.php` | Abstract PDO connectivity test class (shared DB assertions). |
| `tests/MariaDbConnectionTest.php` | PHP → MariaDB connectivity via PDO. |
| `tests/PostgresConnectionTest.php` | PHP → PostgreSQL connectivity via PDO. |
| `tests/SqliteConnectionTest.php` | PHP → SQLite connectivity via PDO. |
| `web/index.php` | JSON endpoint: writes to primary, reads back via a `PREFER_REPLICA` client. |
| `scripts/setup.sh` | gum-driven build + start + PHPUnit install. |
| `scripts/test.sh` | gum-driven CLI + web test runner (HTTPie + jq validation). |
| `scripts/teardown.sh` | gum-driven stop + cleanup. |
| `openresty/default.conf` | OpenResty vhost on `:80` (Laravel public root). |
| `openresty/web.conf` | OpenResty vhost on `:8080` serving `web/`. |
| `nginx/default.conf` | Stock nginx vhost on `:80` — kept for reference. |
| `nginx/web.conf` | Stock nginx vhost on `:8080` — kept for reference. |
| `php.dockerfile` | PHP 8.4 FPM with Rust toolchain and valkey-glide compiled from source. |
| `openresty.dockerfile` | OpenResty (nginx + LuaJIT) — the web server in use. |
| `nginx.dockerfile` | Stock Nginx stable-alpine — kept for reference. |
| `valkey.dockerfile` | Valkey 9 Alpine image. |
| `docker-compose.yml` | Full stack: OpenResty, PHP-FPM, MariaDB, standalone Valkey + read-only replica. |

## Architecture

```mermaid
flowchart TD
    nginx@{ shape: rect, label: "Nginx" }
    php@{ shape: rect, label: "PHP-FPM \n + valkey glide" }
    v@{ shape: lin-cyl, label: "valkey \n :6379 \n (standalone)" }
    vn@{ shape: processes, label: "valkey-node-{1,2,3} \n :700, :7001, :7002 \n (cluster)"}

    START[ ] --- |:80| nginx
    nginx --- |fastcgi: 9000| php
    php --> v 
    php --> vn

    style START fill:#FFFFFF00, stroke:#FFFFFF00;
```

## Configuration

The valkey-glide version is configurable via build arg:

```bash
docker compose build --build-arg VALKEY_GLIDE_VERSION=1.0.0
```

## Stopping

```bash
docker compose down
```

## Notes

- The cluster uses 3 primary nodes with no replicas (suitable for local dev/testing).
- `valkey-cluster-init` is a one-shot container that creates the cluster topology and exits.
- Alpine Linux is **not** supported by valkey-glide — the Dockerfile uses Debian-based PHP.
- Requires PHP 8.1+ (8.4 used here).
