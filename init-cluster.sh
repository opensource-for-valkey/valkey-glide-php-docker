#!/usr/bin/env bash
set -e

echo "Waiting for nodes to be ready..."
sleep 3

docker exec -it valkey-1 valkey-cli \
  --cluster create \
  172.30.0.11:7001 \
  172.30.0.12:7002 \
  172.30.0.13:7003 \
  # 172.30.0.14:7004 \
  # 172.30.0.15:7005 \
  # 172.30.0.16:7006 \
  # --cluster-replicas 1 \
  --cluster-yes

echo "Cluster created. Checking status..."
docker exec -it valkey-1 valkey-cli -p 7001 cluster info