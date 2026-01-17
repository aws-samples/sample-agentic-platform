# Makefile for the Agentic Platform
# Run `make help` to see available commands

.PHONY: help install test test-unit test-cov lint security labs clean

PORT ?= 8080

#==============================================================================
# Help
#==============================================================================

help:
	@echo "Agentic Platform - Make Commands"
	@echo ""
	@echo "Setup & Testing:"
	@echo "  make install              Install dependencies"
	@echo "  make test                 Run all tests"
	@echo "  make test-unit            Run unit tests only"
	@echo "  make test-cov             Run tests with coverage"
	@echo "  make lint                 Run linter"
	@echo "  make security             Run gitleaks"
	@echo ""
	@echo "Run Locally:"
	@echo "  make dev <name> [PORT=<port>]      Run agent or MCP server locally"
	@echo "  make service <name>                Run a gateway service locally"
	@echo ""
	@echo "Build & Deploy:"
	@echo "  make build <name>                  Build container image"
	@echo "  make deploy-eks <name>             Build + deploy to EKS"
	@echo "  make deploy-ac <name>              Build + deploy to AgentCore"
	@echo ""
	@echo "Available:"
	@echo "  Agents:   agentic_chat, agentic_rag, jira_agent, langgraph_chat, strands_glue_athena"
	@echo "  MCP:      bedrock_kb_mcp_server"
	@echo "  Services: memory_gateway, retrieval_gateway"
	@echo ""
	@echo "Other:"
	@echo "  make labs                 Start Jupyter Lab"
	@echo "  make clean                Clean cache files"

#==============================================================================
# Setup & Testing
#==============================================================================

install:
	uv sync

test:
	uv run pytest

test-unit:
	uv run pytest tests/unit/

test-cov:
	uv run pytest --cov=src/agentic_platform --cov-report=term-missing

lint:
	uv run ruff check src/

security:
	gitleaks detect .

#==============================================================================
# Run Locally
#==============================================================================

# make dev agentic_chat
dev:
	$(eval NAME := $(filter-out $@,$(MAKECMDGOALS)))
	@if [ -z "$(NAME)" ]; then echo "Usage: make dev <name>"; exit 1; fi
	cd src && uv run --env-file agentic_platform/agent/$(NAME)/.env -- \
		uvicorn agentic_platform.agent.$(NAME).server:app --reload --port $(PORT)

# make dev:mcp bedrock_kb_mcp_server
dev\:mcp:
	$(eval NAME := $(filter-out $@,$(MAKECMDGOALS)))
	@if [ -z "$(NAME)" ]; then echo "Usage: make dev:mcp <name>"; exit 1; fi
	cd src && uv run --env-file agentic_platform/mcp_server/$(NAME)/.env -- \
		python -m agentic_platform.mcp_server.$(NAME).server

# make service memory_gateway
service:
	$(eval NAME := $(filter-out $@,$(MAKECMDGOALS)))
	@if [ -z "$(NAME)" ]; then echo "Usage: make service <name>"; exit 1; fi
	cd src && uv run --env-file agentic_platform/service/$(NAME)/.env -- \
		uvicorn agentic_platform.service.$(NAME).server:app --reload

#==============================================================================
# Build & Deploy
#==============================================================================

# make build agentic-chat
build:
	$(eval NAME := $(filter-out $@,$(MAKECMDGOALS)))
	@if [ -z "$(NAME)" ]; then echo "Usage: make build <name>"; exit 1; fi
	./deploy/build-container.sh $(NAME) agent

# make build:mcp bedrock-kb-mcp-server
build\:mcp:
	$(eval NAME := $(filter-out $@,$(MAKECMDGOALS)))
	@if [ -z "$(NAME)" ]; then echo "Usage: make build:mcp <name>"; exit 1; fi
	./deploy/build-container.sh $(NAME) mcp_server

# make deploy-eks agentic-chat
deploy-eks:
	$(eval NAME := $(filter-out $@,$(MAKECMDGOALS)))
	@if [ -z "$(NAME)" ]; then echo "Usage: make deploy-eks <name>"; exit 1; fi
	./deploy/build-container.sh $(NAME) agent
	./deploy/deploy-application.sh $(NAME) agent

# make deploy-eks:mcp bedrock-kb-mcp-server
deploy-eks\:mcp:
	$(eval NAME := $(filter-out $@,$(MAKECMDGOALS)))
	@if [ -z "$(NAME)" ]; then echo "Usage: make deploy-eks:mcp <name>"; exit 1; fi
	./deploy/build-container.sh $(NAME) mcp_server
	./deploy/deploy-mcp-server.sh $(NAME)

# make deploy-ac agentic_chat
deploy-ac:
	$(eval NAME := $(filter-out $@,$(MAKECMDGOALS)))
	@if [ -z "$(NAME)" ]; then echo "Usage: make deploy-ac <name>"; exit 1; fi
	./deploy/build-container.sh $(NAME) agent
	cd infrastructure/stacks/agentcore-runtime && terraform apply -var-file="$(NAME).tfvars" -auto-approve

deploy-gateways:
	./deploy/deploy-gateways.sh --build

#==============================================================================
# Other
#==============================================================================

labs:
	uv run jupyter lab

clean:
	find . -type d -name "__pycache__" -exec rm -rf {} + 2>/dev/null || true
	find . -type d -name ".pytest_cache" -exec rm -rf {} + 2>/dev/null || true
	find . -type f -name "*.pyc" -delete 2>/dev/null || true

# Catch-all for positional arguments
%:
	@:
