up:
	docker compose up -d
	bash FunctionalSolution/scripts/host-setup.sh

down:
	docker compose down -v

restart: down up

.PHONY: up down restart
