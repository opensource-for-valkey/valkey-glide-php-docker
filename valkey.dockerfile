# valkey-bundle ships Valkey plus the official modules (json, search, bloom,
# ldap). ValkeyJSON is required by Valkey Admin, which runs JSON.TYPE while
# scanning keys for its dashboard; stock valkey/valkey has no modules and the
# dashboard fails with "unknown command 'JSON.TYPE'". The bundle entrypoint
# auto-loads every .so in /usr/lib/valkey, including when compose overrides
# the command (e.g. the replica's --replicaof), so no extra config is needed.
FROM valkey/valkey-bundle:latest
