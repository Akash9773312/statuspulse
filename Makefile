.PHONY: build up down logs test clean shell image-size

COMPOSE := docker compose
APP_PORT ?= 8000

build:
	$(COMPOSE) build

up:
	$(COMPOSE) up -d

down:
	$(COMPOSE) down

logs:
	$(COMPOSE) logs -f

test:
	@echo "Waiting for health endpoint..."
	@for i in 1 2 3 4 5 6 7 8 9 10; do \
		curl -fsS http://localhost:$(APP_PORT)/health >/dev/null 2>&1 && break; \
		sleep 3; \
	done
	@curl -fsS http://localhost:$(APP_PORT)/health | python3 -m json.tool
	@echo "\nHealth check passed."

clean:
	$(COMPOSE) down -v --rmi local --remove-orphans

shell:
	$(COMPOSE) exec app bash || $(COMPOSE) exec app sh

image-size:
	@docker images statuspulse* --format '{{.Repository}}:{{.Tag}}\t{{.Size}}' 2>/dev/null || \
		docker images --format '{{.Repository}}:{{.Tag}}\t{{.Size}}' | grep -E 'statuspulse|$(shell basename $$(pwd))' || true
