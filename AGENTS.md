# Agentic Platform - Agent Guide

## Quick Reference: Which AGENTS.md to Read

| Change Type | Read This File |
|-------------|----------------|
| **Agent/Service code** | [`src/agentic_platform/AGENTS.md`](src/agentic_platform/AGENTS.md) |
| **Infrastructure (Terraform)** | [`infrastructure/AGENTS.md`](infrastructure/AGENTS.md) |
| **Kubernetes/Helm** | [`k8s/AGENTS.md`](k8s/AGENTS.md) |
| **Bootstrap/CloudFormation** | [`bootstrap/AGENTS.md`](bootstrap/AGENTS.md) |
| **Tests** | [`tests/AGENTS.md`](tests/AGENTS.md) |
| **Labs (learning only)** | [`labs/AGENTS.md`](labs/AGENTS.md) |

## Critical Rules (All Changes)

```bash
# After code changes
make test

# After EVERY commit
make security

# After Terraform changes
checkov -d .
```

## Make Commands

Run `make help` for all available commands. Key commands:

```bash
# Setup
make install              # Install dependencies

# Testing
make test                 # Run all tests
make test-unit            # Run unit tests only
make test-cov             # Run tests with coverage

# Run locally (agents)
make dev agentic_chat              # Run an agent locally
make dev agentic_rag PORT=8004     # Run with custom port

# Run locally (MCP servers)
make dev:mcp bedrock_kb_mcp_server # Run an MCP server locally

# Run locally (services)
make service memory_gateway        # Run a service locally

# Build & Deploy (agents)
make build agentic-chat              # Build container
make deploy-eks agentic-chat         # Build + deploy to EKS
make deploy-ac agentic_chat          # Build + deploy to AgentCore

# Build & Deploy (MCP servers)
make build:mcp bedrock-kb-mcp-server       # Build MCP container
make deploy-eks:mcp bedrock-kb-mcp-server  # Build + deploy MCP to EKS

# Code quality
make lint                 # Run linter
make security             # Run gitleaks
```

---

# Agent Development Guide

This guide explains the agent architecture, folder structure, and how to build new agents in the platform.

## Table of Contents

- [Architecture Overview](#architecture-overview)
- [Folder Structure](#folder-structure)
- [Agent Patterns](#agent-patterns)
- [Building a New Agent](#building-a-new-agent)
- [Core Components](#core-components)
- [Deployment](#deployment)
- [Testing](#testing)

## Architecture Overview

The platform uses a microservice architecture where each agent runs as an independent FastAPI server. Agents share a common core package that provides:

- **Standardized API models** (`AgenticRequest`, `AgenticResponse`)
- **Gateway clients** (LLM, Memory, Retrieval)
- **Middleware** (Authentication, Telemetry, Request Context)
- **Observability** (OpenTelemetry integration)
- **Converters** (Framework-specific adapters)

### Key Principles

1. **Separation of Concerns**: Server → Controller → Agent logic
2. **Framework Agnostic**: Support multiple agent frameworks (LangGraph, PydanticAI, Strands, DIY)
3. **Secure by Design**: JWT authentication, no direct IAM roles on agents
4. **Observable**: Built-in telemetry and tracing
5. **Containerized**: Each agent is independently deployable

## Folder Structure

```
src/agentic_platform/
├── agent/                          # Agent implementations
│   ├── agentic_chat/               # Strands-based chat agent
│   │   ├── server.py               # FastAPI server (thin layer)
│   │   ├── controller/             # Business logic
│   │   │   └── agentic_chat_controller.py
│   │   ├── agent/                  # Agent implementation
│   │   │   └── agentic_chat_agent.py
│   │   ├── prompt/                 # Prompt templates
│   │   │   └── agentic_chat_prompt.py
│   │   ├── streaming/              # Streaming utilities
│   │   │   └── strands_converter.py
│   │   ├── Dockerfile              # Container definition
│   │   ├── requirements.txt        # Dependencies
│   │   └── .env                    # Local config
│   │
│   ├── agentic_rag/                # RAG agent with Bedrock KB
│   │   ├── server.py
│   │   ├── controller/
│   │   ├── agent/
│   │   ├── tool/                   # Agent-specific tools
│   │   ├── prompt/
│   │   ├── Dockerfile
│   │   ├── requirements.txt
│   │   └── .env
│   │
│   ├── langgraph_chat/             # LangGraph-based agent
│   │   ├── server.py
│   │   ├── chat_controller.py
│   │   ├── chat_workflow.py        # LangGraph workflow
│   │   ├── chat_prompt.py
│   │   ├── Dockerfile
│   │   ├── requirements.txt
│   │   └── .env
│   │
│   ├── jira_agent/                 # Jira integration agent
│   │   ├── server.py
│   │   ├── jira_controller.py
│   │   ├── jira_agent.py
│   │   ├── jira_prompt.py
│   │   ├── Dockerfile
│   │   ├── requirements.txt
│   │   └── .env
│   │
│   └── strands_glue_athena/        # AWS Glue/Athena agent
│       ├── server.py
│       ├── agent_controller.py
│       ├── agent_service.py
│       ├── tools/                  # AWS-specific tools
│       │   ├── athena_tools.py
│       │   └── glue_tools.py
│       ├── Dockerfile
│       ├── requirements.txt
│       └── README.md
│
├── core/                           # Shared core functionality
│   ├── client/                     # Gateway clients
│   │   ├── llm_gateway/
│   │   ├── memory_gateway/
│   │   └── retrieval_gateway/
│   ├── models/                     # Shared data models
│   │   ├── api_models.py           # AgenticRequest/Response
│   │   ├── memory_models.py        # Message, Content types
│   │   ├── streaming_models.py     # StreamEvent
│   │   ├── tool_models.py
│   │   └── ...
│   ├── middleware/                 # FastAPI middleware
│   │   ├── auth/
│   │   ├── configure_middleware.py
│   │   ├── telemetry_middleware.py
│   │   └── request_context_middleware.py
│   ├── converter/                  # Framework converters
│   │   ├── langchain_converters.py
│   │   ├── pydanticai_converters.py
│   │   ├── strands_converters.py
│   │   └── litellm_converters.py
│   ├── decorator/                  # Decorators
│   │   ├── api_error_decorator.py
│   │   └── toolspec_decorator.py
│   ├── observability/              # Telemetry
│   │   ├── observability_facade.py
│   │   └── provider/
│   ├── tool/                       # Shared tools
│   └── db/                         # Database utilities
│
├── service/                        # Gateway services
│   ├── litellm_gateway/            # LLM proxy
│   ├── memory_gateway/             # Conversation memory
│   └── retrieval_gateway/          # Vector search
│
├── tool/                           # Reusable tools
│   ├── calculator/
│   ├── weather/
│   └── retrieval/
│
└── mcp_server/                     # MCP server implementations
    └── bedrock_kb_mcp_server/
```

## Agent Patterns

### Pattern 1: Standard Agent (Recommended)

**Structure:**
```
agent_name/
├── server.py           # FastAPI endpoints
├── controller/         # Business logic
├── agent/              # Agent implementation
├── prompt/             # Prompt templates
├── tool/               # Agent-specific tools (optional)
├── Dockerfile
├── requirements.txt
└── .env
```

**Example:** `agentic_chat`, `agentic_rag`

### Pattern 2: Simple Agent

**Structure:**
```
agent_name/
├── server.py           # FastAPI endpoints
├── controller.py       # Business logic
├── agent.py            # Agent implementation
├── prompt.py           # Prompt templates
├── Dockerfile
├── requirements.txt
└── .env
```

**Example:** `jira_agent`, `langgraph_chat`

### Pattern 3: Service Agent

**Structure:**
```
agent_name/
├── server.py           # FastAPI endpoints
├── agent_controller.py
├── agent_service.py    # Core logic
├── tools/              # Multiple tools
├── Dockerfile
├── requirements.txt
└── README.md
```

**Example:** `strands_glue_athena`

## Building a New Agent

### Step 1: Create Agent Directory

```bash
mkdir -p src/agentic_platform/agent/my_agent/{controller,agent,prompt}
cd src/agentic_platform/agent/my_agent
```

### Step 2: Create Server (server.py)

```python
"""FastAPI server for My Agent."""

import logging
from fastapi import FastAPI
import uvicorn

from agentic_platform.core.middleware.configure_middleware import configuration_server_middleware
from agentic_platform.core.models.api_models import AgenticRequest, AgenticResponse
from agentic_platform.core.decorator.api_error_decorator import handle_exceptions
from agentic_platform.agent.my_agent.controller import my_agent_controller

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

app = FastAPI(title="My Agent")

# Configure middleware (auth, telemetry, request context)
configuration_server_middleware(app, path_prefix="/api/my-agent")

@app.post("/invocations", response_model=AgenticResponse)
@app.post("/invoke", response_model=AgenticResponse)
@handle_exceptions(status_code=500, error_prefix="My Agent API Error")
async def invoke(request: AgenticRequest) -> AgenticResponse:
    """Invoke the agent."""
    return await my_agent_controller.invoke(request)

@app.get("/health")
@app.get("/ping")
async def health() -> dict[str, str]:
    """Health check endpoint."""
    return {"status": "healthy"}

if __name__ == "__main__":
    uvicorn.run(app, host="0.0.0.0", port=8080)
```

### Step 3: Create Controller (controller/my_agent_controller.py)

```python
"""Controller for My Agent."""

import logging
from agentic_platform.core.models.api_models import AgenticRequest, AgenticResponse
from agentic_platform.agent.my_agent.agent.my_agent_impl import MyAgent

logger = logging.getLogger(__name__)

# Module-level agent instance
agent = MyAgent()

async def invoke(request: AgenticRequest) -> AgenticResponse:
    """Invoke the agent with a standard response."""
    return agent.invoke(request)
```

### Step 4: Create Agent Implementation (agent/my_agent_impl.py)

```python
"""My Agent implementation."""

import logging
from agentic_platform.core.models.api_models import AgenticRequest, AgenticResponse
from agentic_platform.core.models.memory_models import Message
from agentic_platform.core.client.llm_gateway.llm_gateway_client import LLMGatewayClient

logger = logging.getLogger(__name__)

class MyAgent:
    """Agent implementation."""

    def __init__(self):
        """Initialize the agent."""
        self.llm_client = LLMGatewayClient.get_client()
        # Initialize your agent framework here

    def invoke(self, request: AgenticRequest) -> AgenticResponse:
        """Process the request and return a response."""
        user_message = request.message
        
        # Your agent logic here
        # Use self.llm_client to call LLMs
        # Use gateway clients for memory, retrieval, etc.
        
        response_message = Message.from_text("assistant", "Response text")
        
        return AgenticResponse(
            message=response_message,
            session_id=request.session_id,
            metadata={}
        )
```

### Step 5: Create Prompt (prompt/my_agent_prompt.py)

```python
"""Prompt templates for My Agent."""

SYSTEM_PROMPT = """You are a helpful assistant.

Your role is to...
"""

def get_system_prompt() -> str:
    """Get the system prompt."""
    return SYSTEM_PROMPT
```

### Step 6: Create Dependencies (requirements.txt)

```txt
# Add agent-specific dependencies
# Core dependencies are in pyproject.toml
langchain>=0.1.0
# or
pydantic-ai>=0.1.0
# or
strands-agents>=0.1.0
```

### Step 7: Create Environment File (.env)

```bash
# LLM Gateway
LITELLM_API_ENDPOINT=http://localhost:4000
LITELLM_KEY=sk-your-key

# Environment
ENVIRONMENT=local

# Agent-specific config
MY_AGENT_CONFIG=value
```

### Step 8: Create Dockerfile

```dockerfile
FROM python:3.12-slim

WORKDIR /app

# Copy source code
COPY src/ /app/src/
COPY pyproject.toml /app/

# Install dependencies
RUN pip install --no-cache-dir uv && \
    uv pip install --system -e .

# Install agent-specific dependencies
COPY src/agentic_platform/agent/my_agent/requirements.txt /app/
RUN uv pip install --system -r requirements.txt

# Expose port
EXPOSE 8080

# Run server
CMD ["uvicorn", "agentic_platform.agent.my_agent.server:app", "--host", "0.0.0.0", "--port", "8080"]
```

### Step 9: Add to Makefile

```makefile
.PHONY: my-agent

my-agent:
	cd src && \
	uv run --env-file agentic_platform/agent/my_agent/.env -- uvicorn agentic_platform.agent.my_agent.server:app --reload --port 8080
```

### Step 10: Create Helm Values

Create `k8s/helm/values/applications/my-agent-values.yaml`:

```yaml
serviceName: my-agent
image:
  repository: <account-id>.dkr.ecr.<region>.amazonaws.com/my-agent
  tag: latest
  pullPolicy: Always

service:
  port: 8080
  targetPort: 8080

resources:
  requests:
    memory: "512Mi"
    cpu: "250m"
  limits:
    memory: "1Gi"
    cpu: "500m"

env:
  - name: ENVIRONMENT
    value: "production"
  - name: LITELLM_API_ENDPOINT
    value: "http://litellm-gateway:4000"
```

## Core Components

### AgenticRequest

Standard request model for all agents:

```python
class AgenticRequest(BaseModel):
    message: Message              # User message
    session_id: Optional[str]     # Conversation ID
    stream: bool = False          # Enable streaming
    max_tokens: Optional[int]     # Token limit
    include_thinking: bool = False # Include reasoning
    context: Optional[Dict]       # Additional context
```

### AgenticResponse

Standard response model:

```python
class AgenticResponse(BaseModel):
    message: Message              # Assistant response
    session_id: str               # Conversation ID
    metadata: Optional[Dict]      # Additional metadata
```

### Message

Unified message format:

```python
class Message(BaseModel):
    role: str                     # "user", "assistant", "system"
    content: List[Content]        # Text, images, audio, JSON
    tool_calls: List[ToolCall]    # Tool invocations
    tool_results: List[ToolResult] # Tool outputs
```

### Gateway Clients

#### LLM Gateway Client

```python
from agentic_platform.core.client.llm_gateway.llm_gateway_client import LLMGatewayClient

client = LLMGatewayClient.get_client()
response = client.chat_completion(
    model="anthropic.claude-sonnet-4",
    messages=[{"role": "user", "content": "Hello"}]
)
```

#### Memory Gateway Client

```python
from agentic_platform.core.client.memory_gateway.memory_gateway_client import MemoryGatewayClient

client = MemoryGatewayClient()
history = client.get_memory(session_id="123")
```

#### Retrieval Gateway Client

```python
from agentic_platform.core.client.retrieval_gateway.retrieval_gateway_client import RetrievalGatewayClient

client = RetrievalGatewayClient()
results = client.search(query="search term", top_k=5)
```

### Middleware

All agents automatically get:

- **Authentication**: JWT token validation
- **Telemetry**: OpenTelemetry tracing
- **Request Context**: Thread-local request data
- **Path Prefix**: API versioning

Configure via:

```python
from agentic_platform.core.middleware.configure_middleware import configuration_server_middleware

configuration_server_middleware(app, path_prefix="/api/my-agent")
```

### Observability

```python
from agentic_platform.core.observability.observability_facade import ObservabilityFacade

obs = ObservabilityFacade()

# Tracing
with obs.tracer.start_as_current_span("operation"):
    # Your code
    pass

# Metrics
obs.meter.create_counter("requests").add(1)

# Logging
obs.logger.info("Message")
```

## Deployment

### Local Development

```bash
# Run locally
make my-agent

# Test
curl -X POST http://localhost:8080/invoke \
  -H "Content-Type: application/json" \
  -d '{
    "message": {
      "role": "user",
      "content": [{"type": "text", "text": "Hello"}]
    },
    "session_id": "test"
  }'
```

### Build Container

```bash
./deploy/build-container.sh my-agent agent
```

### Deploy to Kubernetes

```bash
# Build and deploy
./deploy/deploy-application.sh my-agent agent --build

# Or deploy only
./deploy/deploy-application.sh my-agent agent
```

### Verify Deployment

```bash
# Check pods
kubectl get pods -l app=my-agent

# Check logs
kubectl logs -l app=my-agent -f

# Port forward for testing
kubectl port-forward svc/my-agent 8080:8080
```

## Testing

### Unit Tests

Create `tests/unit/agent/test_my_agent.py`:

```python
import pytest
from agentic_platform.agent.my_agent.agent.my_agent_impl import MyAgent
from agentic_platform.core.models.api_models import AgenticRequest

def test_my_agent():
    agent = MyAgent()
    request = AgenticRequest.from_text("Hello")
    response = agent.invoke(request)
    
    assert response.message.role == "assistant"
    assert response.session_id == request.session_id
```

### Integration Tests

Create `tests/integ/agent/test_my_agent_integration.py`:

```python
import pytest
from fastapi.testclient import TestClient
from agentic_platform.agent.my_agent.server import app

client = TestClient(app)

def test_invoke_endpoint():
    response = client.post("/invoke", json={
        "message": {
            "role": "user",
            "content": [{"type": "text", "text": "Hello"}]
        },
        "session_id": "test"
    })
    
    assert response.status_code == 200
    data = response.json()
    assert "message" in data
    assert "session_id" in data
```

### Run Tests

```bash
# All tests
uv run pytest

# Specific test
uv run pytest tests/unit/agent/test_my_agent.py

# With coverage
uv run pytest --cov=src/agentic_platform/agent/my_agent
```

## Best Practices

1. **Keep servers thin**: Business logic goes in controllers
2. **Use gateway clients**: Don't access AWS services directly
3. **Follow the pattern**: Use existing agents as templates
4. **Add observability**: Use the observability facade
5. **Handle errors**: Use the `@handle_exceptions` decorator
6. **Document prompts**: Keep prompts in separate files
7. **Test thoroughly**: Write unit and integration tests
8. **Use type hints**: Leverage Pydantic models
9. **Log appropriately**: Use structured logging
10. **Secure by default**: Let middleware handle auth

## Framework Examples

### Using LangGraph

```python
from langgraph.graph import StateGraph
from agentic_platform.core.converter.langchain_converters import LangChainConverter

class MyLangGraphAgent:
    def __init__(self):
        self.graph = self._build_graph()
        self.converter = LangChainConverter()
    
    def _build_graph(self):
        workflow = StateGraph(dict)
        # Define your graph
        return workflow.compile()
    
    def invoke(self, request: AgenticRequest) -> AgenticResponse:
        lc_messages = self.converter.to_langchain_messages(request.message)
        result = self.graph.invoke({"messages": lc_messages})
        return self.converter.to_agentic_response(result, request.session_id)
```

### Using PydanticAI

```python
from pydantic_ai import Agent
from agentic_platform.core.converter.pydanticai_converters import PydanticAIConverter

class MyPydanticAgent:
    def __init__(self):
        self.agent = Agent("openai:gpt-4")
        self.converter = PydanticAIConverter()
    
    def invoke(self, request: AgenticRequest) -> AgenticResponse:
        result = self.agent.run_sync(request.user_text)
        return self.converter.to_agentic_response(result, request.session_id)
```

### Using Strands

```python
from strands import Agent
from agentic_platform.core.converter.strands_converters import StrandsConverter

class MyStrandsAgent:
    def __init__(self):
        self.agent = Agent(model="claude-3-sonnet")
        self.converter = StrandsConverter()
    
    def invoke(self, request: AgenticRequest) -> AgenticResponse:
        result = self.agent.run(request.user_text)
        return self.converter.to_agentic_response(result, request.session_id)
```

## Troubleshooting

### Agent won't start

- Check `.env` file exists and has correct values
- Verify dependencies in `requirements.txt`
- Check logs: `kubectl logs -l app=my-agent`

### Authentication errors

- Ensure middleware is configured
- Check JWT token is valid
- Verify Cognito configuration

### Gateway connection errors

- Check gateway service is running
- Verify endpoint URLs in environment
- Check network policies in Kubernetes

### Performance issues

- Review resource limits in Helm values
- Check for memory leaks
- Enable profiling with observability tools
- Review LLM token usage

## Additional Resources

- [Core Models Documentation](src/agentic_platform/core/models/)
- [Gateway Clients Documentation](src/agentic_platform/core/client/)
- [Deployment Guide](DEPLOYMENT.md)
- [Labs](labs/README.md)
- [Infrastructure](infrastructure/README.md)
