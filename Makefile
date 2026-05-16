.PHONY: up-standalone down-standalone up-cluster down-cluster

up-standalone:
	docker compose up -d --build

down-standalone:
	docker compose down -v

up-cluster:
	docker compose -f docker-compose.cluster.yml up -d --build
	@if [ ! -f data/valkey-1/nodes.conf ]; then \
		echo "Initializing cluster..."; \
		./init-cluster.sh; \
	else \
		echo "Cluster already initialized, skipping init."; \
	fi

down-cluster:
	docker compose -f docker-compose.cluster.yml down -v