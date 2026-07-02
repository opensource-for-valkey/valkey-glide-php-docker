-- Seed script for the valkeyglide database.
-- Runs on first container start via /docker-entrypoint-initdb.d/.
-- The database + valkeyglide user are created from MARIADB_* env vars
-- (see .env); this script just ensures the schema and demo data exist.

CREATE DATABASE IF NOT EXISTS `valkeyglide`
    CHARACTER SET utf8mb4
    COLLATE utf8mb4_unicode_ci;

USE `valkeyglide`;

-- Demo table so the database is not empty on first boot.
CREATE TABLE IF NOT EXISTS `cache_entries` (
    `id`         BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
    `key_name`   VARCHAR(191) NOT NULL,
    `value`      TEXT NULL,
    `created_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (`id`),
    UNIQUE KEY `uq_cache_entries_key_name` (`key_name`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

INSERT INTO `cache_entries` (`key_name`, `value`) VALUES
    ('greeting', 'Hello from valkey-glide-php!')
ON DUPLICATE KEY UPDATE `value` = VALUES(`value`);
