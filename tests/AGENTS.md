# Testing Guide for AI Agents

This document provides context for AI agents writing and modifying tests.

## Critical Rules

**Before modifying ANY test:**

1. List existing tests for the file/module
2. Write a test plan explaining:
   - What tests exist
   - What needs to change and why
   - What new tests are needed
   - What tests should be removed
3. **Get user approval on the test plan**
4. Then implement changes

**After EVERY test change:**

```bash
make test
```

## Make Commands

Use these make commands for testing:

```bash
make test                 # Run all tests
make test-unit            # Run unit tests only
make test-integ           # Run integration tests only
make test-cov             # Run tests with coverage report
make lint                 # Run linter
```

## Test Strategy

### Principles

1. **1:1 Mapping**: One test file per source file
2. **Unit First**: Prefer unit tests over integration tests
3. **Mock External**: Mock all external dependencies (AWS, databases, APIs)
4. **Fast Tests**: Unit tests should run in milliseconds
5. **Isolated**: Tests should not depend on each other

### Test Types

| Type | Location | Purpose | Speed |
|------|----------|---------|-------|
| Unit | `tests/unit/` | Test single functions/classes in isolation | Fast (<100ms) |
| Integration | `tests/integ/` | Test components working together | Medium |
| E2E | `tests/e2e/` | Test full workflows | Slow |

## Directory Structure

Tests mirror the source structure:

```
tests/
├── conftest.py                     # Root fixtures (env vars, mocks)
├── __init__.py
│
├── unit/                           # Unit tests
│   ├── conftest.py                 # Unit-specific fixtures
│   ├── __init__.py
│   │
│   ├── core/                       # Tests for src/agentic_platform/core/
│   │   ├── models/
│   │   │   ├── test_api_models.py      # → core/models/api_models.py
│   │   │   └── test_memory_models.py   # → core/models/memory_models.py
│   │   ├── client/
│   │   │   └── test_litellm_gateway_client.py
│   │   └── converter/
│   │       └── test_litellm_converters.py
│   │
│   ├── agent/                      # Tests for src/agentic_platform/agent/
│   │   ├── diy_agent/
│   │   │   ├── test_diy_agent.py           # → agent/diy_agent/agent.py
│   │   │   └── test_diy_agent_controller.py # → agent/diy_agent/controller.py
│   │   └── pydanticai_agent/
│   │       ├── test_pyai_agent.py
│   │       └── test_pyai_agent_controller.py
│   │
│   └── service/                    # Tests for src/agentic_platform/service/
│       ├── memory_gateway/
│       │   ├── api/
│       │   └── prompt/
│       └── retrieval_gateway/
│           ├── api/
│           └── client/
│
└── integ/                          # Integration tests
    ├── conftest.py                 # Integration-specific fixtures
    ├── __init__.py
    │
    ├── gateways/
    │   ├── memory_gateway/
    │   │   └── test_memory_gateway.py
    │   └── retrieval_gateway/
    │       └── test_retrieval_gateway.py
    │
    └── workflows/
        ├── evaluator_optimizer/
        ├── orchestrator/
        ├── parallelization/
        ├── prompt_chaining/
        └── routing/
```

## File Naming Convention

| Source File | Test File |
|-------------|-----------|
| `my_module.py` | `test_my_module.py` |
| `my_agent.py` | `test_my_agent.py` |
| `my_controller.py` | `test_my_controller.py` |

## Running Tests

Use make commands (recommended):

```bash
make test                 # All tests
make test-unit            # Unit tests only
make test-integ           # Integration tests only
make test-cov             # With coverage report
```

Or use pytest directly:

```bash
# All tests
uv run pytest

# Unit tests only
uv run pytest tests/unit/

# Integration tests only  
uv run pytest tests/integ/

# Specific directory
uv run pytest tests/unit/core/models/

# Specific file
uv run pytest tests/unit/core/models/test_api_models.py

# Specific test function
uv run pytest tests/unit/core/models/test_api_models.py::test_agentic_request_from_text

# Specific test class
uv run pytest tests/unit/agent/diy_agent/test_diy_agent.py::TestDiyAgent

# By marker
uv run pytest -m unit
uv run pytest -m integration
uv run pytest -m "not slow"

# With coverage
uv run pytest --cov=src/agentic_platform

# Verbose
uv run pytest -v

# Stop on first failure
uv run pytest -x

# Show print statements
uv run pytest -s
```

## Test Markers

Available markers (defined in `pytest.ini`):

```python
@pytest.mark.unit          # Unit test (default)
@pytest.mark.integration   # Requires external services
@pytest.mark.e2e           # End-to-end test
@pytest.mark.slow          # Takes >1 second
@pytest.mark.asyncio       # Async test
```

## Fixtures

### Root Fixtures (`tests/conftest.py`)

The root conftest provides:

- **Environment variables**: All required env vars are set
- **Database mocks**: PostgreSQL, DynamoDB mocked
- **AWS mocks**: boto3 clients mocked
- **`mock_database_dependencies`**: Auto-used fixture that mocks all DB connections

### Using Fixtures

```python
# Fixtures are auto-injected by name
def test_something(mock_database_dependencies):
    # Database is already mocked
    pass

# Create custom fixtures
@pytest.fixture
def my_agent():
    with patch('some.dependency'):
        return MyAgent()

def test_agent(my_agent):
    result = my_agent.invoke(request)
    assert result is not None
```

## Writing Tests

### Unit Test Template

```python
"""Tests for module_name.py

Tests the ModuleName class/functions.
"""
import pytest
from unittest.mock import Mock, patch, MagicMock, AsyncMock

from agentic_platform.path.to.module import MyClass
from agentic_platform.core.models.api_models import AgenticRequest, AgenticResponse


class TestMyClass:
    """Tests for MyClass."""
    
    @pytest.fixture
    def instance(self):
        """Create instance with mocked dependencies."""
        with patch('agentic_platform.path.to.dependency'):
            return MyClass()
    
    def test_method_returns_expected_type(self, instance):
        """Test that method returns correct type."""
        result = instance.method()
        
        assert isinstance(result, ExpectedType)
    
    def test_method_with_invalid_input(self, instance):
        """Test method handles invalid input."""
        with pytest.raises(ValueError):
            instance.method(invalid_input)
    
    def test_method_calls_dependency(self, instance):
        """Test method calls external dependency correctly."""
        with patch.object(instance, 'dependency') as mock_dep:
            mock_dep.return_value = "result"
            
            result = instance.method()
            
            mock_dep.assert_called_once_with(expected_args)


class TestMyFunction:
    """Tests for standalone function."""
    
    def test_function_basic(self):
        """Test basic functionality."""
        result = my_function("input")
        
        assert result == "expected"
```

### Integration Test Template

```python
"""Integration tests for my_agent.

Tests the full request/response cycle through the FastAPI server.
"""
import pytest
from fastapi.testclient import TestClient

from agentic_platform.agent.my_agent.server import app


@pytest.fixture
def client():
    """Create test client for the server."""
    return TestClient(app)


class TestMyAgentServer:
    """Integration tests for my_agent server endpoints."""
    
    def test_ping_endpoint(self, client):
        """Test /ping returns healthy status."""
        response = client.get("/ping")
        
        assert response.status_code == 200
        assert response.json() == {"status": "healthy"}
    
    def test_health_endpoint(self, client):
        """Test /health returns healthy status."""
        response = client.get("/health")
        
        assert response.status_code == 200
    
    @pytest.mark.integration
    def test_invocations_endpoint(self, client):
        """Test /invocations processes request correctly."""
        request_body = {
            "message": {
                "role": "user",
                "content": [{"type": "text", "text": "Hello"}]
            }
        }
        
        response = client.post("/invocations", json=request_body)
        
        assert response.status_code == 200
        data = response.json()
        assert "message" in data
        assert "session_id" in data
    
    @pytest.mark.integration
    def test_invocations_with_session_id(self, client):
        """Test /invocations preserves session_id."""
        request_body = {
            "message": {
                "role": "user",
                "content": [{"type": "text", "text": "Hello"}]
            },
            "session_id": "test-session-123"
        }
        
        response = client.post("/invocations", json=request_body)
        
        assert response.status_code == 200
        assert response.json()["session_id"] == "test-session-123"
```

### Async Test Template

```python
"""Tests for async functions."""
import pytest
from unittest.mock import AsyncMock, patch


@pytest.mark.asyncio
async def test_async_function():
    """Test async function."""
    with patch('module.dependency', new_callable=AsyncMock) as mock_dep:
        mock_dep.return_value = "result"
        
        result = await async_function()
        
        assert result == "expected"
```

## Mocking Patterns

### Mock External Services

```python
# Mock LLM Gateway
with patch('agentic_platform.core.client.llm_gateway.llm_gateway_client.LLMGatewayClient') as mock:
    mock.chat_invoke.return_value = LLMResponse(...)

# Mock Memory Gateway
with patch('agentic_platform.core.client.memory_gateway.memory_gateway_client.MemoryGatewayClient') as mock:
    mock.get_session_context.return_value = SessionContext(...)

# Mock boto3
with patch('boto3.client') as mock_client:
    mock_client.return_value.invoke.return_value = {...}
```

### Mock at Import Time

```python
# In conftest.py or at top of test file
import sys
from unittest.mock import MagicMock

sys.modules['problematic_module'] = MagicMock()
```

## Test Plan Template

Before modifying tests, create this plan:

```markdown
## Test Plan for [source file path]

### Summary
Brief description of what's changing and why.

### Existing Tests
| Test | Purpose | Status |
|------|---------|--------|
| test_function_a | Tests X behavior | Keep |
| test_function_b | Tests Y behavior | Modify |
| test_function_c | Tests Z behavior | Remove |

### Tests to Modify
- `test_function_b`: 
  - Current: Tests old behavior
  - Change: Update to test new behavior
  - Reason: [why the change is needed]

### New Tests Needed
- `test_new_feature`:
  - Purpose: Tests [new behavior]
  - Inputs: [test inputs]
  - Expected: [expected outputs]

### Tests to Remove
- `test_function_c`:
  - Reason: [why it's no longer needed]

### Risks
- [Any risks or concerns with the changes]
```

## Adding Tests for New Code

### New Agent

Create test files mirroring the agent structure:

```
tests/unit/agent/my_agent/
├── __init__.py
├── test_my_agent.py           # Tests agent implementation
└── test_my_agent_controller.py # Tests controller
```

### New Core Module

```
tests/unit/core/new_module/
├── __init__.py
└── test_new_module.py
```

### New Service

```
tests/unit/service/my_service/
├── __init__.py
├── api/
│   └── test_controller.py
└── client/
    └── test_client.py
```

## Common Issues

### Import Errors

If imports fail due to missing dependencies:

```python
# Mock at module level before imports
import sys
from unittest.mock import MagicMock

sys.modules['missing_module'] = MagicMock()

# Then import your code
from agentic_platform.module import MyClass
```

### Async Test Not Running

Ensure you have the marker:

```python
@pytest.mark.asyncio
async def test_async():
    pass
```

### Database Connection Errors

The root `conftest.py` should mock these. If not:

```python
@pytest.fixture(autouse=True)
def mock_db():
    with patch('sqlalchemy.create_engine'):
        yield
```

### Environment Variables

Set in `conftest.py` or use:

```python
@pytest.fixture
def env_vars(monkeypatch):
    monkeypatch.setenv('MY_VAR', 'value')
```
