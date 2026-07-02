-- Seed script for the valkeyglide PostgreSQL database.
-- Runs on first container start via /docker-entrypoint-initdb.d/.
-- The database + valkeyglide user/role are created from POSTGRES_* env
-- vars (see .env); this script runs against that database and just
-- ensures the schema and demo data exist.

-- Demo table so the database is not empty on first boot.
CREATE TABLE IF NOT EXISTS cache_entries (
    id         BIGSERIAL PRIMARY KEY,
    key_name   VARCHAR(191) NOT NULL UNIQUE,
    value      TEXT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

INSERT INTO cache_entries (key_name, value) VALUES
    ('greeting', 'Hello from valkey-glide-php!')
ON CONFLICT (key_name) DO UPDATE SET value = EXCLUDED.value;
