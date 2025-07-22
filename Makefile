ifeq (,$(wildcard .env))
  $(warning Warning: .env file not found)
else ifndef env
  # Extract env value from .env file
  env := $(shell grep -E '^env=' .env | cut -d '=' -f2 | tr -d '"')
  ifeq (,$(env))
    $(warning Warning: env not found in .env)
  endif
endif

ifndef env
$(error Error: 'env' is required. Use: make <target> env=<env> services="svc1 svc2" or define env in .env)
endif

# Compose override path: docker-compose-overrides/{UPPERCASE_ENV_DIR}/docker-compose.{env}.yaml
ENV_DIR := $(shell echo $(env) | cut -d '-' -f 1)
OVERRIDE_FILE := docker-compose-overrides/$(ENV_DIR)/docker-compose.$(env).yaml

FORCE_RECREATE_FLAG := $(if $(filter 1,$(ENABLE_FORCE_RECREATE)),--force-recreate,)
REMOVE_ORPHANS_FLAG := $(if $(or $(services),$(filter 1,$(DISABLE_REMOVE_ORPHANS))),,--remove-orphans)
REMOVE_ANSI_FLAG := $(if $(filter 1,$(DISABLE_ANSI)),,--ansi never)

DOCKER_COMPOSE_COMMAND=docker compose $(REMOVE_ANSI_FLAG) -p peekup-pay \
	-f docker-compose.yaml \
	-f $(OVERRIDE_FILE) 

# Function to validate services parameter
define validate_services
	@cmd_args="$(MAKEOVERRIDES)"; \
	if echo "$$cmd_args" | grep -vE "services=|env=" | grep -q ".*="; then \
		echo "Error: Only 'services' and 'env' parameters are allowed. Use: make $(1) env=dev services=\"svc\""; \
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

.DEFAULT_GOAL := __default
__default:
	@echo "Error: No target specified. Please specify a target explicitly (e.g., deploy, restart)."
	@exit 1

.PHONY: deploy pre-deploy restart stop down pull build safe-pull safe-build reload-caddy git-pull __default