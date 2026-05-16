#!/usr/bin/env sh
set -e

PORT=${PORT:-6379}
PERSIST=${PERSIST:-yes}

if [ "$MODE" = "cluster" ]; then
  echo "Starting Valkey in cluster mode on port $PORT (persist=$PERSIST)"
  if [ "$PERSIST" = "yes" ]; then
    exec valkey-server \
      --port "$PORT" \
      --cluster-enabled yes \
      --cluster-config-file /data/nodes.conf \
      --cluster-node-timeout 5000 \
      --appendonly yes \
      --appendfilename appendonly.aof \
      --dir /data \
      --dbfilename dump.rdb \
      --cluster-announce-ip "$ANNOUNCE_IP" \
      --cluster-announce-port "$PORT"
  else
    exec valkey-server \
      --port "$PORT" \
      --cluster-enabled yes \
      --cluster-config-file /data/nodes.conf \
      --cluster-node-timeout 5000 \
      --save "" \
      --appendonly no \
      --cluster-announce-ip "$ANNOUNCE_IP" \
      --cluster-announce-port "$PORT"
  fi
else
  echo "Starting Valkey in standalone mode on port $PORT (persist=$PERSIST)"
  if [ "$PERSIST" = "yes" ]; then
    exec valkey-server \
      --port "$PORT" \
      --appendonly yes \
      --appendfilename appendonly.aof \
      --dir /data \
      --dbfilename dump.rdb
  else
    exec valkey-server \
      --port "$PORT" \
      --save "" \
      --appendonly no
  fi
fi