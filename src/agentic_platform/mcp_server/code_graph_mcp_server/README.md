# Code Graph MCP Server

Parses a local codebase into a code ontology graph and exposes graph query tools via MCP. 

Source code never leaves your machine — only the derived graph is queried.

## What it answers

- "If I rename `configuration_server_middleware()`, what files need updating?"
- "What does `MemoryGatewayClient` depend on?"
- "What would break if I delete `agentic_platform.core.models.memory_models`?"

## Tools exposed

| Tool | Description |
|---|---|
| `trace_impact` | Full impact analysis — callers + importers combined. Start here for any "what breaks if I change X" question |
| `find_callers` | Who calls this function? Returns file + line for each call site |
| `find_importers` | What files import this module? |
| `find_dependencies` | What does this module/class/function depend on? |
| `get_branches` | Branch map for a single function, a whole file, or an entire call chain (`walk=True`). Routes between graph lookup and fresh parse automatically |
| `rebuild` | Rebuild the graph — incremental (single file) or full. Incremental mode is called by the file-watch Kiro hook |
| `run_query` | Execute a custom Python query against the raw NetworkX graph |
| `graph_stats` | Node/edge counts to confirm graph loaded correctly |

### `get_branches` — branch map for any function, file, or call chain

Returns every decision point (if/elif/else, try/except, match/case, ternary) annotated with line numbers, condition text, enclosing scope, and a summary of each arm.

**Parameters**

| Parameter | Type | Default | Description |
|---|---|---|---|
| `scope` | str | `""` | Function/method, optionally dotted, e.g. `"MyClass.my_method"` |
| `file_path` | str | `""` | Path to the source file (absolute or relative to `REPO_PATH`). Required if `scope` is empty or not in the graph |
| `walk` | bool | `False` | If `True`, BFS from `scope` as entry point and collect branches across all reachable functions in the call chain |

**Routing**

- `scope` only → graph lookup (fast, cached)
- `scope` + `walk=True` → BFS walk, returns branches for every function reachable from the entry point
- `file_path` only → fresh tree-sitter parse of the whole file
- `scope` + `file_path` → fresh parse, scoped to that function
- `scope` misses the graph → falls back to `file_path` parse if given

Returns `source: "graph"`, `"parse"`, or `"walk"` so callers can tell which path ran.

**Use cases**

- **Test generation** — get the full branch map before writing a single test case. Use `walk=True` to map an entire agent's conditional logic in one call
- **Migration validation** — walk the old system's branches, build a test harness, then run it against the new system
- **Code review** — surface all conditional logic changed in a diff
- **Complexity analysis** — `cyclomatic_complexity` ranks files/functions for refactoring. `walk=True` gives total complexity for a subsystem
- **Security audits** — find bare `except:` clauses, auth-bypass `if environment == 'local'` conditions

## How it works

Source files are parsed with [tree-sitter](https://tree-sitter.github.io/tree-sitter/) — a fast, incremental parser that produces a concrete syntax tree for each file without executing any code. Per-language adapters walk the AST and extract entities (functions, classes, modules) and relationships (calls, imports, inheritance) into a graph model.

That graph is stored in [NetworkX](https://networkx.org/), an in-memory directed multigraph. When you ask "what calls `foo`?", it's a graph traversal — not a text search — so it handles aliases, method calls, and cross-file references that grep would miss.

The graph is exposed to your IDE via the [Model Context Protocol (MCP)](https://modelcontextprotocol.io/), a standard interface for giving LLMs access to external tools. The IDE calls the tools, the LLM synthesizes the answer.

Note: If not using the Kiro hook, use the `rebuild` tool after major file changes.

## Supported languages

Python, TypeScript, JavaScript, Java, Terraform (HCL)

## Quick Setup (Kiro)

```bash
bash src/agentic_platform/mcp_server/code_graph_mcp_server/setup.sh /path/to/your/repo
```

The script:
1. Creates a `.venv` and installs all dependencies
2. Registers the MCP server in `~/.kiro/settings/mcp.json`
3. Copies `hooks/kiro-file-update.json` to `~/.kiro/hooks/` so the graph updates automatically on save

Then restart Kiro (or reconnect via Command Palette → "MCP") and start asking questions.

For other clients, see the Manual setup section below.

## Manual setup

Find your MCP config file and add:

```json
{
  "mcpServers": {
    "code-graph": {
      "command": "/path/to/.venv/bin/python3.12",
      "args": ["-m", "agentic_platform.mcp_server.code_graph_mcp_server.server", "stdio"],
      "env": {
        "REPO_PATH": "/path/to/your/repo",
        "PYTHONPATH": "/path/to/sample-agentic-platform/src"
      }
    }
  }
}
```

Kiro only: also copy `hooks/kiro-file-update.json` to `~/.kiro/hooks/code-graph-file-update.json`. 

## Future Scaling

The current implementation is intentionally simple with NetworkX in memory, local files on disk. It works well for a single developer querying their own repo.

When this becomes a team tool, the natural evolution is:

- Replace NetworkX with a persistent graph database (e.g. Amazon Neptune) so the graph survives restarts and can be shared across developers
- Run the server as a container (ECS/Fargate) instead of a local process
- Trigger graph rebuilds from CI/CD on every merge to main, rather than on developer machines
- Extend `REPO_PATH` to support pulling source from GitHub or S3 at build time, so the server never needs local file access

The `GraphStore` interface in `graph.py` is already abstracted for this so swapping the backend wouldn't require changes anywhere else.
