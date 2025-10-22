.PHONY: langgraph-chat
.PHONY: llm-gateway
.PHONY: evaluator-optimizer
.PHONY: prompt-chaining
.PHONY: routing
.PHONY: parallelization
.PHONY: orchestrator
.PHONY: diy-agent
.PHONY: memory-gateway
.PHONY: retrieval-gateway
.PHONY: knowledge-base
.PHONY: pydanticai-agent
.PHONY: agentic_chat
.PHONY: agentic-rag
# Makefile for running servers locally with UV and the correct environment variables.
# Make sure to fill in your .env file with the correct values.

agentic-chat:
	cd src && \
	uv run --env-file agentic_platform/agent/agentic_chat/.env -- uvicorn agentic_platform.agent.agentic_chat.server:app --reload --port 8003


langgraph-chat:
	cd src && \
	uv run --env-file agentic_platform/chat/langgraph_chat/.env -- uvicorn agentic_platform.chat.langgraph_chat.server:app --reload

prompt-chaining:
	cd src && \
	uv run --env-file agentic_platform/workflow/prompt_chaining/.env -- uvicorn agentic_platform.workflow.prompt_chaining.server:app --reload

routing:
	cd src && \
	uv run --env-file agentic_platform/workflow/routing/.env -- uvicorn agentic_platform.workflow.routing.server:app --reload

parallelization:
	cd src && \
	uv run --env-file agentic_platform/workflow/parallelization/.env -- uvicorn agentic_platform.workflow.parallelization.server:app --reload

orchestrator:
	cd src && \
	uv run --env-file agentic_platform/workflow/orchestrator/.env -- uvicorn agentic_platform.workflow.orchestrator.server:app --reload

evaluator-optimizer:
	cd src && \
	uv run --env-file agentic_platform/workflow/evaluator_optimizer/.env -- uvicorn agentic_platform.workflow.evaluator_optimizer.server:app --reload

diy-agent:
	cd src && \
	uv run --env-file agentic_platform/agent/diy_agent/.env -- uvicorn agentic_platform.agent.diy_agent.server:app --reload

pydanticai-agent:
	cd src && \
	uv run --env-file agentic_platform/agent/pydanticai_agent/.env -- uvicorn agentic_platform.agent.pydanticai_agent.server:app --reload

llm-gateway:
	cd src && \
	uv run --env-file agentic_platform/service/llm_gateway/.env -- uvicorn agentic_platform.service.llm_gateway.server:app --reload

memory-gateway:
	cd src && \
	uv run --env-file agentic_platform/service/memory_gateway/.env -- uvicorn agentic_platform.service.memory_gateway.server:app --reload

agentic-rag:
	cd src && \
	uv run --env-file agentic_platform/agent/agentic_rag/.env -- uvicorn agentic_platform.agent.agentic_rag.server:app --reload --port 8004

retrieval-gateway:
	cd src && \
	uv run --env-file agentic_platform/service/retrieval_gateway/.env -- uvicorn agentic_platform.service.retrieval_gateway.server:app --reload
