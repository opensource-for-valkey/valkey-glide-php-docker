-- Seed script for the valkeyglide SQLite database.
-- SQLite is file-based: there is no server container. This script is
-- applied to ./sqlite/valkeyglide.sqlite by scripts/setup.sh (or run it
-- manually: sqlite3 sqlite/valkeyglide.sqlite < databases-sqlite.sql).

-- Demo table so the database is not empty on first boot.
CREATE TABLE IF NOT EXISTS cache_entries (
    id         INTEGER PRIMARY KEY AUTOINCREMENT,
    key_name   TEXT NOT NULL UNIQUE,
    value      TEXT,
    created_at TEXT NOT NULL DEFAULT (datetime('now'))
);

INSERT INTO cache_entries (key_name, value) VALUES
    ('greeting', 'Hello from valkey-glide-php!')
ON CONFLICT (key_name) DO UPDATE SET value = excluded.value;
