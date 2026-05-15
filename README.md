# Docker Valkey-Glide PHP

A Docker environment for developing with [valkey-glide-php](https://github.com/valkey-io/valkey-glide-php) — includes Nginx, PHP-FPM, and both standalone and cluster Valkey instances.

## Prerequisites

- Docker & Docker Compose

## Quick Start

```bash
git clone https://github.com/Valkey-PHP/valkey-glide-php-docker.git
cd valkey-glide-php-docker

# Build and start all services
docker compose up -d --build
```

## Testing

Run CLI demos:
```bash
# Install PHPUnit in the PHP container
docker exec valkey-glide-php-docker-php composer require --dev phpunit/phpunit

# Test standalone Valkey connection
docker exec valkey-glide-php-docker-php ./vendor/bin/phpunit --bootstrap /var/www/html/helpers.php /var/www/html/ValkeyStandaloneTest.php
```

**Note:** Cluster configuration is still work in progress.

## Project Structure

| File | Description |
|------|-------------|
| `src/ValkeyTestBase.php` | Abstract PHPUnit test class with all 18 test methods. |
| `src/ValkeyStandaloneTest.php` | Standalone test implementation (extends ValkeyTestBase). |
| `php.dockerfile` | PHP 8.4 FPM with Rust toolchain and valkey-glide compiled from source. |
| `nginx.dockerfile` | Nginx stable-alpine with PHP-FPM integration. |
| `valkey.dockerfile` | Valkey 9 Alpine image. |
| `docker-compose.yml` | Full stack: Nginx, PHP-FPM, MariaDB, standalone Valkey. |

## Architecture

```
                        ┌─────────────┐
    :80 ───────────────►│    Nginx    │
                        └──────┬──────┘
                               │ fastcgi :9000
                               ▼
                        ┌─────────────┐
                        │  PHP-FPM    │
                        │  + valkey   │
                        │    glide    │
                        └──┬──────┬───┘
                           │      │
                           ▼      ▼
              ┌─────────────┐  ┌────────────────────────┐
              │   valkey    │  │  valkey-node-{1,2,3}   │
              │  :6379      │  │  :7000, :7001, :7002   │
              │ (standalone)│  │  (cluster)             │
              └─────────────┘  └────────────────────────┘
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
