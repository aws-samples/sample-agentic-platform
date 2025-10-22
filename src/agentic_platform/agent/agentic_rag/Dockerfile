# Stage 1: Builder stage with dependencies
# checkov:skip=CKV_DOCKER_2: Kubernetes handles health checks via probes instead of Docker HEALTHCHECK
FROM ghcr.io/astral-sh/uv:python3.12-bookworm-slim AS builder

# Create a non-root user and group in the builder stage
RUN groupadd appgroup && useradd -g appgroup appuser

# Configure UV for container environment
ENV UV_SYSTEM_PYTHON=1 UV_COMPILE_BYTECODE=1

# Set working directory
WORKDIR /app

# Copy requirements from agentic_chat directory
COPY src/agentic_platform/agent/agentic_chat/requirements.txt .

RUN uv pip install -r requirements.txt

# Stage 2: Server stage that inherits from builder
FROM builder AS server

# Set working directory
WORKDIR /app

# Copy source from the agentic-platform root (build context should be agentic-platform root)
COPY --chown=appuser:appgroup src/agentic_platform/core/ agentic_platform/core/
COPY --chown=appuser:appgroup src/agentic_platform/agent/agentic_rag/ agentic_platform/agent/agentic_rag/

# Set PYTHONPATH to include the app directory
# ENV PYTHONPATH=/app:$PYTHONPATH

# Expose the port your FastAPI app will run on
EXPOSE 8080

# Switch to the non-root user
USER appuser

# Command to run the FastAPI server using uvicorn
CMD ["uvicorn", "agentic_platform.agent.agentic_rag.server:app", "--host", "0.0.0.0", "--port", "8080"]
