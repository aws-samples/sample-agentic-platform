# Labs Guide for AI Agents

## TL;DR

**Labs are for learning only. Ignore for platform changes.**

The `labs/` directory contains Jupyter notebooks for educational purposes. They:
- Import code from `src/agentic_platform/` (packaged via `uv`)
- Do NOT contribute code to the platform
- Can be ignored when making platform-level changes

## When to Modify Labs

Only modify labs when:
- User explicitly asks to update a lab/notebook
- Fixing a broken import after `src/` changes
- Adding new educational content

**Do NOT modify labs for:**
- Platform feature development
- Bug fixes in platform code
- Infrastructure changes

## Structure

```
labs/
├── module1/          # Prompt Engineering & Evaluation
│   └── notebooks/    # Jupyter notebooks
├── module2/          # Common Agentic Patterns
│   └── notebooks/
├── module3/          # Building Agentic Applications
│   └── notebooks/
├── module4/          # Multi-Agent Systems & MCP
│   └── notebooks/
├── module5/          # Deployment and Infrastructure
│   └── notebooks/
└── README.md
```

## How Labs Work

1. `uv sync` installs `src/agentic_platform/` as a package
2. Notebooks import from `agentic_platform.*`
3. `uv run jupyter lab` starts the notebook environment

```python
# In notebooks, imports work like this:
from agentic_platform.core.models.api_models import AgenticRequest
from agentic_platform.core.client.llm_gateway import LLMGatewayClient
```

## Running Labs

```bash
# Install dependencies
uv sync

# Start Jupyter
uv run jupyter lab
```

## If Imports Break

When `src/` code changes break lab imports:

1. Check what changed in `src/agentic_platform/`
2. Update the import in the affected notebook
3. Test the notebook runs

## Module Overview

| Module | Topic | Platform Required |
|--------|-------|-------------------|
| 1 | Prompt Engineering & Evaluation | No |
| 2 | Common Agentic Patterns | No |
| 3 | Building Agentic Applications | No |
| 4 | Multi-Agent Systems & MCP | No |
| 5 | Deployment and Infrastructure | Yes |

Only Module 5 requires the deployed platform infrastructure.
