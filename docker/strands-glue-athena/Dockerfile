# Stage 1: Builder stage with dependencies
# checkov:skip=CKV_DOCKER_2: Kubernetes handles health checks via probes instead of Docker HEALTHCHECK
FROM python:3.12.10-alpine3.21 AS builder

# Create a non-root user and group in the builder stage
RUN addgroup -S appgroup && adduser -S appuser -G appgroup

# Set working directory
WORKDIR /app

# Copy the requirements file
COPY src/agentic_platform/agent/strands_glue_athena/requirements.txt .

# Install dependencies
RUN pip install --no-cache-dir -r requirements.txt

# Stage 2: Server stage that inherits from builder
# nosemgrep: missing-image-version
FROM builder AS server

# Set working directory
WORKDIR /app

# Copy source now that the dependencies are installed
COPY --chown=appuser:appgroup src/agentic_platform/core/ agentic_platform/core/
COPY --chown=appuser:appgroup src/agentic_platform/agent/strands_glue_athena/ agentic_platform/agent/strands_glue_athena/

# Set the working directory to where the server.py is located
WORKDIR /app/

# Set PYTHONPATH to include the app directory
ENV PYTHONPATH=/app:$PYTHONPATH

# Expose the port your FastAPI app will run on
EXPOSE 8000

# Switch to the non-root user
USER appuser

# Command to run the FastAPI server using uvicorn
CMD ["uvicorn", "agentic_platform.agent.strands_glue_athena.server:app", "--host", "0.0.0.0", "--port", "8000"]
