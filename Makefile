FORCE_RECREATE_FLAG := $(if $(filter 1,$(ENABLE_FORCE_RECREATE)),--force-recreate,)
REMOVE_ORPHANS_FLAG := $(if $(or $(services),$(filter 1, $(DISABLE_REMOVE_ORPHANS))),,--remove-orphans)
REMOVE_ANSI_FLAG := $(if $(filter 1,$(DISABLE_ANSI)),,--ansi never)

DOCKER_COMPOSE_COMMAND=docker compose $(REMOVE_ANSI_FLAG) -p peekup

# Function to validate services parameter
define validate_services
	@cmd_args="$(MAKEOVERRIDES)"; \
	if echo "$$cmd_args" | grep -v "services=" | grep -q ".*="; then \
		echo "Error: Only 'services' parameter is allowed. Please use: make $(1) services=\"service_name\""; \
		exit 1; \
	fi
endef

install-docker:
	@./scripts/install-docker.sh

install-gpu-drivers:
	@./scripts/install-gpu-drivers.sh

setup-daemon:
	@./scripts/setup-daemon.sh

migrate-volume:
	@./scripts/migrate-volume.sh
	
setup-webhook:
	@./scripts/webhook/setup-webhook.sh
	
reload-caddy:
	@echo "Reloading caddy"
	$(DOCKER_COMPOSE_COMMAND) exec -w /etc/caddy caddy caddy reload || true

#used for validating service parameter in dev(to improve code clarity)
pre-deploy:
	$(call validate_services,deploy)

deploy: pre-deploy $(if $(filter 1,$(ENABLE_GIT_PULL)),git-pull,) $(if $(filter 1,$(DISABLE_PULL)),,pull build) reload-caddy
	@if [ -z "$(services)" ]; then \
		echo "Notice: No services specified. Deploying all services."; \
	fi
	$(DOCKER_COMPOSE_COMMAND) up -d $(FORCE_RECREATE_FLAG) $(REMOVE_ORPHANS_FLAG) $(services)
	
restart:
	$(call validate_services,restart)
	@if [ -z "$(services)" ]; then \
		echo "Notice: No services specified. Restarting all services."; \
	fi
	$(DOCKER_COMPOSE_COMMAND) restart $(services)

stop:
	$(call validate_services,stop)
	@if [ -z "$(services)" ]; then \
		echo "Notice: No services specified. Stopping all services."; \
	fi
	$(DOCKER_COMPOSE_COMMAND) stop $(services)

down:
	$(call validate_services,down)
	@if [ -z "$(services)" ]; then \
		echo "Notice: No services specified. Bringing down all services."; \
	fi
	$(DOCKER_COMPOSE_COMMAND) down $(services)
	
pull:
	$(call validate_services,pull)
	@if [ -z "$(services)" ]; then \
		echo "Notice: No services specified. Pulling all services."; \
	fi
	$(DOCKER_COMPOSE_COMMAND) pull $(services)

build:
	$(call validate_services,build)
	@if [ -z "$(services)" ]; then \
		echo "Notice: No services specified. Building all services."; \
	fi
	$(DOCKER_COMPOSE_COMMAND) build $(services)

git-pull: 
	git pull

.PHONY: deploy pre-deploy restart stop down pull build safe-pull safe-build reload-caddy git-pull
