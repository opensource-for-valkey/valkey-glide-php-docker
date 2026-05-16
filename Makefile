.PHONY: build-standalone up-standalone down-standalone build-cluster up-cluster down-cluster

build-standalone:
	docker compose build

up-standalone:
	docker compose up -d

down-standalone:
	docker compose down -v

stop-standalone:
	docker compose stop

build-cluster:
	docker compose -f docker-compose.cluster.yml build

up-cluster:
	docker compose -f docker-compose.cluster.yml up -d
	@if [ ! -f data/valkey-1/nodes.conf ]; then \
		echo "Initializing cluster..."; \
		./init-cluster.sh; \
	else \
		echo "Cluster already initialized, skipping init."; \
	fi

down-cluster:
	docker compose -f docker-compose.cluster.yml down -v

stop-cluster:
	docker compose -f docker-compose.cluster.yml stop