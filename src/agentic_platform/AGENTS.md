# Source Code Guide for AI Agents

This document provides context for AI agents writing code in the agentic_platform package.

## Critical Rules

**After EVERY change:**

```bash
# Run tests
make test

# Check for secrets (after commit)
make security
```

**Before modifying tests:**
1. Review existing tests for the file being changed
2. Write out a test plan (what exists, what needs to change, what's new)
3. Get user approval on the test plan
4. Then implement changes

## Make Commands

Use these make commands for common operations:

```bash
# Testing & Quality
make test                 # Run all tests
make test-unit            # Run unit tests only
make test-cov             # Run tests with coverage
make lint                 # Run linter
make security             # Run gitleaks

# Run locally
make dev agentic_chat              # Run an agent
make dev:mcp bedrock_kb_mcp_server # Run an MCP server
make service memory_gateway        # Run a service

# Build & Deploy
make build agentic-chat              # Build agent container
make build:mcp bedrock-kb-mcp-server # Build MCP container
make deploy-eks agentic-chat         # Deploy agent to EKS
make deploy-eks:mcp bedrock-kb-mcp-server  # Deploy MCP to EKS
make deploy-ac agentic_chat          # Deploy to AgentCore
```

## Architecture Overview

```
src/agentic_platform/
├── core/           # Shared library (copied into all Dockerfiles)
├── agent/          # Independent agent services
├── service/        # Gateway services (LLM, Memory, Retrieval)
├── tool/           # Reusable tools
└── mcp_server/     # MCP server implementations
```

### Deployment Model

All containers follow the **AgentCore interface** for portability:
- **Endpoint**: `/invocations` (and `/invoke` alias)
- **Health**: `/ping` (and `/health` alias)
- **Port**: `8080`

This allows deployment to **any compute substrate**:
- **EKS** (Kubernetes)
- **ECS** (Fargate/EC2)
- **Bedrock AgentCore**

Choose your substrate at deployment time - the container works everywhere.

```
┌─────────────────────────────────────────────────┐
│              Same Container Image               │
│  (/invocations, /ping, port 8080)              │
└─────────────────────────────────────────────────┘
                      │
        ┌─────────────┼─────────────┐
        ▼             ▼             ▼
   ┌─────────┐   ┌─────────┐   ┌──────────┐
   │   EKS   │   │   ECS   │   │ AgentCore│
   │  (K8s)  │   │(Fargate)│   │(Managed) │
   └─────────┘   └─────────┘   └──────────┘
```

## Core Package (`core/`)

The core package provides shared functionality for all services. It gets copied into every Dockerfile.

### Directory Structure

```
core/
├── models/              # Pydantic data models
│   ├── api_models.py    # AgenticRequest, AgenticResponse
│   ├── memory_models.py # Message, Content, ToolCall, ToolResult
│   ├── streaming_models.py # StreamEvent types
│   ├── llm_models.py    # LLM request/response
│   └── ...
├── client/              # Gateway clients
│   ├── llm_gateway/     # LLMGatewayClient
│   ├── memory_gateway/  # MemoryGatewayClient
│   └── retrieval_gateway/ # RetrievalGatewayClient
├── middleware/          # FastAPI middleware
│   ├── configure_middleware.py  # Main configuration
│   ├── auth/            # JWT authentication
│   ├── path_middleware.py
│   └── request_context_middleware.py
├── converter/           # Framework adapters
│   ├── strands_converters.py
│   ├── langchain_converters.py
│   ├── pydanticai_converters.py
│   └── litellm_converters.py
├── decorator/           # Utility decorators
│   ├── api_error_decorator.py
│   └── toolspec_decorator.py
├── context/             # Request context
├── observability/       # OpenTelemetry
├── db/                  # Database utilities
└── formatter/           # Output formatters
```

### Key Models

#### AgenticRequest / AgenticResponse

Standard API contract for all agents:

```python
from agentic_platform.core.models.api_models import AgenticRequest, AgenticResponse

# Request
class AgenticRequest(BaseModel):
    message: Message              # User message
    session_id: Optional[str]     # Auto-generated if not provided
    stream: bool = False
    max_tokens: Optional[int] = None
    include_thinking: bool = False
    context: Optional[Dict[str, Any]] = {}
    
    # Convenience methods
    @classmethod
    def from_text(cls, text: str, **kwargs) -> "AgenticRequest"
    
    @property
    def user_text(self) -> Optional[str]

# Response
class AgenticResponse(BaseModel):
    message: Message
    session_id: str
    metadata: Optional[Dict[str, Any]] = {}
    
    @property
    def text(self) -> Optional[str]
```

#### Message and Content Types

Unified message format supporting text, images, audio, JSON:

```python
from agentic_platform.core.models.memory_models import (
    Message, TextContent, ImageContent, AudioContent, JsonContent,
    ToolCall, ToolResult
)

# Create a message
message = Message.from_text("user", "Hello")

# Or with multiple content types
message = Message(
    role="assistant",
    content=[
        TextContent(text="Here's the result"),
        JsonContent(content={"key": "value"})
    ]
)

# Access content
text = message.text  # Aggregated text
text_content = message.get_text_content()  # First TextContent block
```

#### Streaming Events

For streaming responses:

```python
from agentic_platform.core.models.streaming_models import (
    StreamEvent, StreamEventType,
    StartEvent, TextDeltaEvent, ToolCallEvent, 
    ToolResultEvent, ErrorEvent, DoneEvent
)

# Yield events in a stream
yield StartEvent(session_id=session_id)
yield TextDeltaEvent(session_id=session_id, text="Hello")
yield DoneEvent(session_id=session_id)
```

### Gateway Clients

#### LLM Gateway

Routes LLM requests through LiteLLM proxy:

```python
from agentic_platform.core.client.llm_gateway.llm_gateway_client import (
    LLMGatewayClient, LiteLLMClientInfo
)

# For direct LLM calls
response = LLMGatewayClient.chat_invoke(request)

# For framework integration (Strands, LangChain, etc.)
client_info: LiteLLMClientInfo = LLMGatewayClient.get_client_info()
# Returns: api_key, api_endpoint
```

#### Memory Gateway

Manages conversation history:

```python
from agentic_platform.core.client.memory_gateway.memory_gateway_client import MemoryGatewayClient

client = MemoryGatewayClient()
session = client.get_session_context(session_id)
client.upsert_session_context(session)
```

#### Retrieval Gateway

Vector search and knowledge base queries:

```python
from agentic_platform.core.client.retrieval_gateway.retrieval_gateway_client import RetrievalGatewayClient

client = RetrievalGatewayClient()
results = client.retrieve(query, top_k=5)
```

### Middleware

Configure middleware for all FastAPI servers:

```python
from agentic_platform.core.middleware.configure_middleware import configuration_server_middleware

app = FastAPI(title="My Agent")
configuration_server_middleware(app, path_prefix="/api/my-agent")
```

This adds:
- **CORS**: Cross-origin requests
- **Path Transform**: Strips ALB path prefix
- **Auth**: JWT validation (skipped in `local` and `agentcore` environments)
- **Request Context**: Thread-local request data

### Decorators

#### Error Handling

```python
from agentic_platform.core.decorator.api_error_decorator import handle_exceptions

@app.post("/invoke")
@handle_exceptions(status_code=500, error_prefix="Agent Error")
async def invoke(request: AgenticRequest) -> AgenticResponse:
    return await controller.invoke(request)
```

### Converters

Convert between platform types and framework-specific types:

```python
# Strands
from agentic_platform.core.converter.strands_converters import StrandsConverter

# LangChain
from agentic_platform.core.converter.langchain_converters import LangChainConverter

# PydanticAI
from agentic_platform.core.converter.pydanticai_converters import PydanticAIConverter

# LiteLLM
from agentic_platform.core.converter.litellm_converters import LiteLLMRequestConverter, LiteLLMResponseConverter
```

## Agents (`agent/`)

Each agent is an independent FastAPI service with its own Dockerfile.

### Agent Structure

```
agent/
└── my_agent/
    ├── server.py              # FastAPI app (thin layer)
    ├── controller/            # Business logic
    │   └── my_agent_controller.py
    ├── agent/                 # Agent implementation
    │   └── my_agent_impl.py
    ├── prompt/                # Prompt templates
    │   └── my_agent_prompt.py
    ├── tool/                  # Agent-specific tools (optional)
    ├── streaming/             # Streaming converters (optional)
    ├── Dockerfile
    ├── requirements.txt       # Agent-specific deps
    └── .env                   # Local config
```

### Creating a New Agent

#### 1. Server (`server.py`)

All servers must implement the AgentCore interface:

```python
"""FastAPI server for My Agent."""
from fastapi import FastAPI
import uvicorn

from agentic_platform.core.middleware.configure_middleware import configuration_server_middleware
from agentic_platform.core.models.api_models import AgenticRequest, AgenticResponse
from agentic_platform.core.decorator.api_error_decorator import handle_exceptions
from agentic_platform.agent.my_agent.controller import my_agent_controller

app = FastAPI(title="My Agent")
configuration_server_middleware(app, path_prefix="/api/my-agent")

# AgentCore interface: /invocations on port 8080
@app.post("/invocations", response_model=AgenticResponse)
@app.post("/invoke", response_model=AgenticResponse)  # Alias for convenience
@handle_exceptions(status_code=500, error_prefix="My Agent Error")
async def invoke(request: AgenticRequest) -> AgenticResponse:
    return await my_agent_controller.invoke(request)

# AgentCore interface: /ping for health checks
@app.get("/ping")
@app.get("/health")  # Alias for K8s probes
async def health():
    return {"status": "healthy"}

if __name__ == "__main__":
    # AgentCore interface: port 8080
    uvicorn.run(app, host="0.0.0.0", port=8080)
```

#### 2. Controller (`controller/my_agent_controller.py`)

```python
"""Controller for My Agent."""
from agentic_platform.core.models.api_models import AgenticRequest, AgenticResponse
from agentic_platform.agent.my_agent.agent.my_agent_impl import MyAgent

# Module-level instance
agent = MyAgent()

async def invoke(request: AgenticRequest) -> AgenticResponse:
    return agent.invoke(request)
```

#### 3. Agent Implementation (`agent/my_agent_impl.py`)

```python
"""My Agent implementation."""
from agentic_platform.core.models.api_models import AgenticRequest, AgenticResponse
from agentic_platform.core.models.memory_models import Message, TextContent
from agentic_platform.core.client.llm_gateway.llm_gateway_client import LLMGatewayClient

class MyAgent:
    def __init__(self):
        # Initialize your agent framework here
        pass

    def invoke(self, request: AgenticRequest) -> AgenticResponse:
        user_text = request.user_text
        
        # Your agent logic here
        response_text = "Response"
        
        return AgenticResponse(
            message=Message(role="assistant", content=[TextContent(text=response_text)]),
            session_id=request.session_id,
            metadata={"agent_type": "my_agent"}
        )
```

#### 4. Dockerfile

```dockerfile
FROM python:3.12-slim
WORKDIR /app

COPY src/ /app/src/
COPY pyproject.toml /app/

RUN pip install --no-cache-dir uv && \
    uv pip install --system -e .

COPY src/agentic_platform/agent/my_agent/requirements.txt /app/
RUN uv pip install --system -r requirements.txt

EXPOSE 8080
CMD ["uvicorn", "agentic_platform.agent.my_agent.server:app", "--host", "0.0.0.0", "--port", "8080"]
```

### Existing Agents

| Agent | Framework | Purpose |
|-------|-----------|---------|
| `agentic_chat` | Strands | General chat with tools |
| `agentic_rag` | Strands | RAG with Bedrock KB |
| `langgraph_chat` | LangGraph | Graph-based workflows |
| `jira_agent` | Strands | Jira integration |
| `strands_glue_athena` | Strands | AWS Glue/Athena queries |

## Services (`service/`)

Gateway services that agents connect to.

### Available Services

| Service | Purpose | Port |
|---------|---------|------|
| `litellm_gateway` | LLM proxy (Bedrock, OpenAI, etc.) | 4000 |
| `memory_gateway` | Conversation history (PostgreSQL) | 4000 |
| `retrieval_gateway` | Vector search (OpenSearch, Bedrock KB) | 4000 |

### Service Structure

```
service/
└── memory_gateway/
    ├── server.py
    ├── api/                 # Controllers
    │   ├── get_session_controller.py
    │   ├── upsert_session_controller.py
    │   └── ...
    ├── client/              # External clients (optional)
    ├── prompt/              # Prompts (optional)
    ├── Dockerfile
    ├── requirements.txt
    └── .env
```

## MCP Servers (`mcp_server/`)

Model Context Protocol servers for tool integration.

### Structure

```
mcp_server/
└── bedrock_kb_mcp_server/
    ├── server.py           # FastMCP server
    ├── Dockerfile
    ├── requirements.txt
    └── .env
```

### Creating an MCP Server

```python
from mcp.server.fastmcp import FastMCP

mcp = FastMCP(
    "my-mcp-server",
    host="0.0.0.0",
    port=8080,
    stateless_http=True
)

@mcp.tool()
def my_tool(query: str) -> str:
    """Tool description."""
    return "result"

if __name__ == "__main__":
    mcp.run()
```

## Tools (`tool/`)

Reusable tools that can be used by any agent.

### Structure

```
tool/
├── calculator/
│   └── calculator_tool.py
├── weather/
│   └── weather_tool.py
└── retrieval/
    ├── retrieval_tool.py
    └── retrieval_tool_prompt.py
```

### Creating a Tool

```python
def my_tool(param: str) -> str:
    """
    Tool description for the LLM.
    
    Args:
        param: Parameter description
        
    Returns:
        Result description
    """
    return f"Result: {param}"
```

## Environment Variables

### Common Variables

```bash
# LLM Gateway
LITELLM_API_ENDPOINT=http://localhost:4000
LITELLM_KEY=sk-xxx

# Environment (affects middleware behavior)
ENVIRONMENT=local  # local, agentcore, or production

# AWS
AWS_DEFAULT_REGION=us-west-2
```

### Agent-Specific Variables

```bash
# RAG Agent
KNOWLEDGE_BASE_ID=xxx

# Jira Agent
JIRA_URL=https://xxx.atlassian.net
JIRA_API_TOKEN=xxx
```

## Local Development

### Run an Agent

```bash
# Using make (recommended)
make agent NAME=agentic_chat
make agent NAME=agentic_rag PORT=8004
make agent NAME=jira_agent PORT=8080
make agent NAME=langgraph_chat
make agent NAME=strands_glue_athena

# Or manually
cd src
uv run --env-file agentic_platform/agent/my_agent/.env -- \
  uvicorn agentic_platform.agent.my_agent.server:app --reload --port 8080
```

### Run a Service

```bash
make service NAME=memory_gateway
make service NAME=retrieval_gateway
```

### Test an Agent

```bash
curl -X POST http://localhost:8080/invocations \
  -H "Content-Type: application/json" \
  -d '{
    "message": {
      "role": "user",
      "content": [{"type": "text", "text": "Hello"}]
    }
  }'

# Health check
curl http://localhost:8080/ping
```

## Deployment

### Build Container

```bash
# Build and push to ECR
./deploy/build-container.sh <agent-name> agent

# Examples
./deploy/build-container.sh agentic-chat agent
./deploy/build-container.sh memory-gateway service
```

### Deploy to Kubernetes (EKS)

```bash
# Deploy with build
./deploy/deploy-application.sh <agent-name> agent --build

# Deploy without build (image already in ECR)
./deploy/deploy-application.sh <agent-name> agent

# Examples
./deploy/deploy-application.sh agentic-chat agent --build
./deploy/deploy-application.sh agentic-rag agent
```

### Helm Values

Create `k8s/helm/values/applications/<agent-name>-values.yaml`:

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

### Verify Deployment

```bash
# Check pods
kubectl get pods -l app=my-agent

# Check logs
kubectl logs -l app=my-agent -f

# Port forward for testing
kubectl port-forward svc/my-agent 8080:8080

# Test via port forward
curl http://localhost:8080/ping
curl -X POST http://localhost:8080/invocations -H "Content-Type: application/json" -d '...'
```

### Deploy to AgentCore

Use the `agentcore-runtime` Terraform stack:

```bash
cd infrastructure/stacks/agentcore-runtime/

# Create tfvars for your agent
cat > my_agent.tfvars << EOF
agent_name = "my-agent"
container_image = "<account-id>.dkr.ecr.<region>.amazonaws.com/my-agent:latest"
EOF

# Deploy
terraform apply -var-file="my_agent.tfvars"
```

## Key Patterns

### 1. Server → Controller → Agent

Keep servers thin. Business logic in controllers. Framework code in agent implementations.

### 2. Use Gateway Clients

Never call AWS services directly from agents. Use gateway clients:
- `LLMGatewayClient` for LLM calls
- `MemoryGatewayClient` for conversation history
- `RetrievalGatewayClient` for vector search

### 3. Standardized Models

Always use `AgenticRequest` and `AgenticResponse` for API contracts.

### 4. Framework Converters

Use converters to translate between platform types and framework types.

### 5. Environment-Aware Middleware

Middleware auto-configures based on `ENVIRONMENT`:
- `local`: No auth
- `agentcore`: No auth (handled by AgentCore)
- Other: JWT auth enabled

## Adding New Code

### New Agent Checklist

1. Create directory structure under `agent/`
2. Implement server.py with AgentCore interface (`/invocations`, `/ping`, port 8080)
3. Implement controller with business logic
4. Implement agent with framework code
5. Add Dockerfile
6. Add requirements.txt
7. Add .env for local development
8. Add to Makefile
9. **Write tests** (see Testing section below)
10. Run `uv run pytest`
11. Create Helm values file in `k8s/helm/values/applications/`
12. Build: `./deploy/build-container.sh my-agent agent`
13. Deploy: `./deploy/deploy-application.sh my-agent agent --build`
14. Run `gitleaks detect .` after commit

### New Tool Checklist

1. Create directory under `tool/`
2. Implement tool function with docstring
3. **Write unit tests** for the tool
4. Run `uv run pytest tests/unit/tool/`
5. Add to agent's tool list
6. Run `gitleaks detect .` after commit

### Modifying Core

1. Changes affect ALL services
2. **Write/update tests first**
3. Run `uv run pytest tests/unit/core/`
4. Test with multiple agents
5. Update converters if models change
6. Run `gitleaks detect .` after commit

## Testing

### Test Structure

Tests mirror the source structure with 1 test file per source file:

```
tests/
├── unit/                           # Fast, isolated tests
│   ├── core/
│   │   ├── models/
│   │   │   ├── test_api_models.py      # Tests api_models.py
│   │   │   └── test_memory_models.py   # Tests memory_models.py
│   │   ├── client/
│   │   │   └── test_litellm_gateway_client.py
│   │   └── converter/
│   │       └── test_litellm_converters.py
│   ├── agent/
│   │   ├── diy_agent/
│   │   │   ├── test_diy_agent.py
│   │   │   └── test_diy_agent_controller.py
│   │   └── pydanticai_agent/
│   │       ├── test_pyai_agent.py
│   │       └── test_pyai_agent_controller.py
│   └── service/
│       ├── memory_gateway/
│       └── retrieval_gateway/
│
├── integ/                          # Tests with real dependencies
│   ├── gateways/
│   │   ├── memory_gateway/
│   │   └── retrieval_gateway/
│   └── workflows/
│
└── conftest.py                     # Shared fixtures
```

### Running Tests

```bash
# All tests
uv run pytest

# Unit tests only
uv run pytest tests/unit/

# Integration tests only
uv run pytest tests/integ/

# Specific file
uv run pytest tests/unit/core/models/test_api_models.py

# Specific test
uv run pytest tests/unit/core/models/test_api_models.py::test_agentic_request_from_text

# With coverage
uv run pytest --cov=src/agentic_platform

# Verbose output
uv run pytest -v
```

### Writing Tests

#### Before Modifying Tests

**Always create a test plan first:**

```
## Test Plan for [file being changed]

### Existing Tests
- test_function_a: Tests X behavior
- test_function_b: Tests Y behavior

### Tests to Modify
- test_function_a: Need to update because [reason]

### New Tests Needed
- test_new_feature: Tests [new behavior]

### Tests to Remove
- test_old_behavior: No longer relevant because [reason]
```

**Get user approval before implementing.**

#### Unit Test Template

```python
"""Tests for my_module.py"""
import pytest
from unittest.mock import Mock, patch, MagicMock

from agentic_platform.agent.my_agent.agent.my_agent_impl import MyAgent
from agentic_platform.core.models.api_models import AgenticRequest, AgenticResponse


class TestMyAgent:
    """Tests for MyAgent class."""
    
    @pytest.fixture
    def agent(self):
        """Create agent instance for testing."""
        with patch('agentic_platform.core.client.llm_gateway.llm_gateway_client.LLMGatewayClient'):
            return MyAgent()
    
    def test_invoke_returns_response(self, agent):
        """Test that invoke returns an AgenticResponse."""
        request = AgenticRequest.from_text("Hello")
        
        response = agent.invoke(request)
        
        assert isinstance(response, AgenticResponse)
        assert response.session_id == request.session_id
    
    def test_invoke_with_empty_message(self, agent):
        """Test invoke handles empty messages."""
        request = AgenticRequest.from_text("")
        
        # Test behavior with empty input
        response = agent.invoke(request)
        
        assert response is not None
```

#### Integration Test Template

```python
"""Integration tests for my_agent."""
import pytest
from fastapi.testclient import TestClient

from agentic_platform.agent.my_agent.server import app


@pytest.fixture
def client():
    """Create test client."""
    return TestClient(app)


class TestMyAgentIntegration:
    """Integration tests for my_agent server."""
    
    def test_health_endpoint(self, client):
        """Test health endpoint returns healthy."""
        response = client.get("/ping")
        
        assert response.status_code == 200
        assert response.json()["status"] == "healthy"
    
    @pytest.mark.integration
    def test_invoke_endpoint(self, client):
        """Test invoke endpoint processes request."""
        response = client.post("/invocations", json={
            "message": {
                "role": "user",
                "content": [{"type": "text", "text": "Hello"}]
            }
        })
        
        assert response.status_code == 200
        assert "message" in response.json()
```

### Test Fixtures

Common fixtures are in `tests/conftest.py`:

```python
# Environment is mocked automatically
# Database connections are mocked
# AWS clients are mocked

# Use fixtures in tests:
def test_something(mock_database_dependencies):
    # Database is already mocked
    pass
```

### Test Markers

```python
@pytest.mark.unit          # Unit test
@pytest.mark.integration   # Integration test
@pytest.mark.e2e           # End-to-end test
@pytest.mark.slow          # Slow running test
@pytest.mark.asyncio       # Async test
```

Run by marker:
```bash
uv run pytest -m unit
uv run pytest -m integration
uv run pytest -m "not slow"
```
