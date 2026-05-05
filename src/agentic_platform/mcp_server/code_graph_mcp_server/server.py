"""
Code Graph MCP Server.

Parses a local codebase into a code ontology graph and exposes graph query
tools via the MCP protocol. Designed to run locally alongside a developer's
workspace — source code never leaves the machine.

## When to use these tools (instead of grep or file reading)

These tools resolve method calls, aliases, cross-file references, and
inheritance that text search misses. **Prefer these tools over grep, file
search, or manual file reading** for any structural question about code
relationships:

  - Impact / migration / swap → start with `trace_impact`
  - Branch map / test planning / complexity → `get_branches` (with `walk=True` for call chains)
  - "Who calls X" → `find_callers`
  - "What imports X" → `find_importers`
  - "What does X depend on" → `find_dependencies`
  - Rankings, aggregations, custom traversals → `run_query`

Grep/search is still the right choice for string content (log messages,
config values, TODOs). The code graph is for structural questions.

## Recommended workflows

**Impact analysis** (rename, delete, migrate, swap):
  1. `trace_impact("ComponentName")` — returns all callers + importers
  2. Read impacted files only if you need implementation details

**Test plan / migration scoping** (map all conditional logic):
  1. `get_branches(scope="jira_controller", walk=True)` — one call
  2. Design test cases: one per branch arm, plus combined-path edge cases

Transport: stdio (for IDE MCP integration)

Usage:
  python -m agentic_platform.mcp_server.code_graph_mcp_server.server
"""

import ast
import json
import logging
import os
from mcp.server.fastmcp import FastMCP
from agentic_platform.mcp_server.code_graph_mcp_server.tool.cache import is_cache_valid, load_cache, save_cache, invalidate_cache
from agentic_platform.mcp_server.code_graph_mcp_server.tool.parser import parse_directory, parse_file
from agentic_platform.mcp_server.code_graph_mcp_server.tool.graph import create_graph_store
from agentic_platform.mcp_server.code_graph_mcp_server.tool import query_tools
from agentic_platform.mcp_server.code_graph_mcp_server.tool.branch_extractor import extract_branches, branch_report_to_dict
logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


class CodeGraphMCPServer:
    """MCP server that exposes code ontology graph query tools."""

    def __init__(self, name: str = "code-graph"):
        self.mcp = FastMCP(
            name,
            instructions="""Code Graph — structural code analysis via graph queries.

WHEN TO USE THESE TOOLS (instead of grep, file reading, or sub-agents):
Use these tools for any question about code relationships — dependencies,
impact, usage, migration scope, or test coverage planning. They resolve
method calls, aliases, cross-file references, and inheritance that text
search misses. Grep/search is still correct for string content (log
messages, config values, TODOs).

DECISION GUIDE:
- Impact / migration / swap / rename / delete → trace_impact (START HERE)
- Test plan covering all conditional logic    → get_branches with walk=True
- "Who calls X"                               → find_callers
- "What imports X"                            → find_importers
- "What does X depend on"                     → find_dependencies
- Rankings, aggregations, custom traversals   → run_query

KEY WORKFLOWS:

1. Impact analysis (rename, delete, migrate, swap components):
   a. trace_impact("ComponentName") — returns all callers + importers
   b. Read impacted files only if you need implementation details

2. Test plan / migration scoping (map all conditional logic):
   a. get_branches(scope="jira_controller", walk=True) — one call
   b. Design test cases: one per branch arm, plus combined-path edge cases

IMPORTANT: For any "what would be affected if I change X" question,
call trace_impact BEFORE reading files or delegating to sub-agents.
The graph gives you the complete, structural answer in one call.""",
        )
        self._graph = None
        self._register_tools()

    def _get_graph(self):
        """Lazy-load the graph from cache if valid, otherwise parse from source."""
        if self._graph is None:
            repo_path = os.getenv("REPO_PATH", ".")

            if is_cache_valid(repo_path):
                logger.info("Loading graph from cache for: %s", repo_path)
                result = load_cache(repo_path)
            else:
                logger.info("Building code graph from: %s", repo_path)
                result = parse_directory(repo_path)
                save_cache(repo_path, result)

            self._graph = create_graph_store()
            self._graph.load(result.nodes, result.edges)
            logger.info("Graph ready: %d nodes, %d edges",
                        self._graph.node_count(), self._graph.edge_count())
        return self._graph

    def _validate_query(self, code: str) -> tuple[bool, str]:
        """
        Validate a run_query code string using AST analysis before execution.

        Blocks imports, deletes, and calls to dangerous builtins. Not a
        hardened sandbox — intended to catch accidental or naive misuse.
        For a shared/networked deployment, disable run_query entirely.
        """
        _BLOCKED_NODES = (ast.Import, ast.ImportFrom, ast.Delete)
        _BLOCKED_CALLS = {"exec", "eval", "open", "compile", "__import__", "breakpoint"}

        try:
            tree = ast.parse(code)
        except SyntaxError as e:
            return False, f"Syntax error: {e}"

        for node in ast.walk(tree):
            if isinstance(node, _BLOCKED_NODES):
                return False, f"Blocked: {type(node).__name__} statements are not allowed"
            if isinstance(node, ast.Call):
                func = node.func
                name = (
                    func.id if isinstance(func, ast.Name)
                    else func.attr if isinstance(func, ast.Attribute)
                    else None
                )
                if name in _BLOCKED_CALLS:
                    return False, f"Blocked: call to '{name}' is not allowed"

        return True, ""

    def _register_tools(self):
        """Register all graph query tools with the MCP server."""

        @self.mcp.tool()
        def trace_impact(node_name: str) -> dict:
            """
            Full blast radius of changing/deleting a function, class, or module.
            Combines callers + importers in one call. **This should be the
            default first tool for any question about what would be affected
            by a change.** Prefer this over grep or reading files — it resolves
            method calls, aliases, and cross-file references text search misses.

            USE THIS TOOL WHEN the user asks:
            - "what breaks / is affected / needs updating if I change X"
            - "if I swap / replace / migrate X to Y, what do I need to touch"
            - "where are all the places affected by changing X"
            - "do I need to update each <thing> if I change <component>"
            - "I need to change X — what's the blast radius"
            - "what uses X", "what depends on X", "safe to remove X"
            - any rename, delete, refactor, migration, or swap question

            After getting results, read impacted files only if you need
            implementation details to answer the user's question.

            Args:
                node_name: Name of the function, class, or module (e.g.,
                           "AuthMiddleware", "Message", "CognitoTokenVerifier").
            """
            return query_tools.trace_impact(self._get_graph(), node_name)

        @self.mcp.tool()
        def find_callers(function_name: str) -> dict:
            """
            Call sites of a function (file + line). Use when you only need
            callers; for full impact (callers + importers) prefer trace_impact.

            USE THIS TOOL WHEN the user asks:
            - "who calls X", "callers of X"
            - "where is X invoked" (when you only need call sites, not imports)

            Args:
                function_name: The function name to look up.
            """
            return query_tools.find_callers(self._get_graph(), function_name)

        @self.mcp.tool()
        def find_dependencies(node_name: str) -> dict:
            """
            What a module, class, or function depends on, grouped by relationship
            (CALLS, IMPORTS, INHERITS). Shows the full dependency tree downward.

            USE THIS TOOL WHEN the user asks:
            - "what does X depend on", "what does X use internally"
            - "what do I need to understand before changing X"
            - onboarding to unfamiliar code or agent

            KEY WORKFLOW — test plan generation:
            When the user asks to build a test plan/suite that captures all
            conditional logic for an agent or module:
              1. Call find_dependencies on the agent's entry point to map
                 everything it calls.
              2. Call get_branches on each key function/method to enumerate
                 every branch (if/else, try/catch, etc.).
              3. Design test cases from the branch map.

            Args:
                node_name: Name of the module, class, or function.
            """
            return query_tools.find_dependencies(self._get_graph(), node_name)

        @self.mcp.tool()
        def find_importers(module_name: str) -> dict:
            """
            Files that import a given module (file + line). Use when you only
            need importers; for full impact (callers + importers) prefer
            trace_impact.

            USE THIS TOOL WHEN the user asks:
            - "what imports X", "what files pull in X"
            - module rename/move planning
            - "where is this model/class referenced" (import-level only)

            Args:
                module_name: The module name to look up.
            """
            return query_tools.find_importers(self._get_graph(), module_name)

        @self.mcp.tool()
        def graph_stats() -> dict:
            """
            Node/edge counts. Use to confirm the graph loaded correctly.
            """
            return query_tools.get_graph_stats(self._get_graph())

        @self.mcp.tool()
        def rebuild(file_path: str = "", repo_path: str = "") -> dict:
            """
            Rebuild the code graph. If file_path is given, incrementally
            re-parses that single file (fast). Otherwise does a full rebuild
            from scratch.

            Incremental mode is called automatically by the Kiro fileEdited
            hook. Full rebuild is useful after git pull, branch switch, or
            mass rename.

            Args:
                file_path: Optional. Absolute or REPO_PATH-relative path to
                           a single changed file. If given, does incremental
                           update. If omitted, does full rebuild.
                repo_path: Optional repo root override (full rebuild only).
                           Defaults to REPO_PATH env.
            """
            # Incremental single-file update
            if file_path:
                graph = self._get_graph()

                if not os.path.isabs(file_path):
                    rp = os.getenv("REPO_PATH", ".")
                    file_path = os.path.join(rp, file_path)

                if not os.path.exists(file_path):
                    return {"status": "skipped", "reason": f"File not found: {file_path}"}

                graph.remove_file(file_path)
                result = parse_file(file_path)
                graph.load(result.nodes, result.edges)
                invalidate_cache(os.getenv("REPO_PATH", "."))

                return {
                    "status": "updated",
                    "file": file_path,
                    "nodes_added": len(result.nodes),
                    "edges_added": len(result.edges),
                    **query_tools.get_graph_stats(graph),
                }

            # Full rebuild
            if repo_path:
                os.environ["REPO_PATH"] = repo_path
            self._graph = None
            graph = self._get_graph()
            return {
                "status": "rebuilt",
                "repo_path": os.getenv("REPO_PATH", "."),
                **query_tools.get_graph_stats(graph),
            }

        @self.mcp.tool()
        def run_query(code: str) -> dict:
            """
            Execute custom Python against the graph for questions the other
            tools don't cover (rankings, aggregations, custom traversals).

            USE THIS TOOL WHEN the user asks:
            - "top N most-called functions", "most complex modules"
            - "all classes inheriting from X"
            - "find all functions matching pattern"
            - any aggregate, ranking, or custom graph traversal query

            Scope available: `G` (NetworkX MultiDiGraph), `idx`
            (dict[name, list[node_id]]), `collections`, `itertools`.
            Node attrs: name, node_type, file, line, language.
            Edge attrs: edge_type ("CALLS" | "IMPORTS" | "INHERITS"), file, line.
            node_type values: "Function", "Class", "Module", "External".

            Must assign output to `result`.

            Example — top 10 most-called functions:
                counts = collections.Counter()
                for u, v, d in G.edges(data=True):
                    if d["edge_type"] == "CALLS" and not v.startswith("external::"):
                        counts[G.nodes[v].get("name")] += 1
                result = counts.most_common(10)

            Args:
                code: Python code. Imports, deletes, exec/eval/open are blocked.
            """
            import collections as _collections
            import itertools as _itertools

            valid, reason = self._validate_query(code)
            if not valid:
                return {"error": reason}

            graph = self._get_graph()
            local_ns = {
                "__builtins__": {},
                "G": graph._graph,
                "idx": graph._name_index,
                "collections": _collections,
                "itertools": _itertools,
            }
            try:
                exec(compile(code, "<run_query>", "exec"), local_ns)
            except Exception as e:
                return {"error": str(e), "type": type(e).__name__}

            if "result" not in local_ns:
                return {"error": "Code did not assign to 'result'"}

            raw = local_ns["result"]
            try:
                json.dumps(raw)
                return {"result": raw}
            except (TypeError, ValueError):
                return {"result": str(raw)}

        @self.mcp.tool()
        def get_branches(
            scope: str = "",
            file_path: str = "",
            walk: bool = False,
        ) -> dict:
            """
            Branch map (if/elif/else, try/catch, switch/case, match/case,
            ternary) with cyclomatic complexity.

            Modes:
              - scope only              → single function, graph lookup (fast)
              - scope + walk=True       → BFS from entry point, collects branches
                                          across every reachable function
              - file_path only          → fresh parse of the whole file
              - scope + file_path       → fresh parse, scoped to function
              - scope misses the graph  → falls back to parsing file_path
                                          if given, else returns found=False

            USE THIS TOOL WHEN the user asks:
            - "what branches / conditional logic does X have"
            - "build a test plan/suite that captures all conditional logic"
            - "what's the total complexity of this subsystem" (use walk=True)
            - "map all conditional logic reachable from X" (use walk=True)
            - "scope a migration — how complex is this call chain" (walk=True)
            - cyclomatic complexity, code review of conditionals

            Args:
                scope: Function/method, optionally dotted: "AuthMiddleware.dispatch".
                file_path: Absolute or REPO_PATH-relative path. Required if
                           scope isn't given or isn't in the graph.
                walk: If True, BFS from scope as entry point and collect
                      branches across all reachable functions. Ignores file_path.

            Returns:
                source ("graph" | "parse" | "walk"), file, language,
                total_branches, cyclomatic_complexity, branches[], summary.
            """
            if not scope and not file_path:
                return {
                    "found": False,
                    "error": "Provide `scope`, `file_path`, or both.",
                }

            # Walk mode: BFS from entry point
            if walk and scope:
                result = query_tools.walk_branches(self._get_graph(), scope)
                return {"source": "walk", **result}

            # Fast path: graph lookup when a scope is given
            if scope:
                graph_result = query_tools.get_branches(self._get_graph(), scope)
                if graph_result.get("found"):
                    return {"source": "graph", **graph_result}
                if not file_path:
                    return graph_result

            # Fresh parse path
            if file_path and not os.path.isabs(file_path):
                repo_path = os.getenv("REPO_PATH", ".")
                file_path = os.path.join(repo_path, file_path)

            report = extract_branches(
                file_path=file_path,
                scope=scope if scope else None,
            )
            return {"source": "parse", **branch_report_to_dict(report)}

    def get_server(self) -> FastMCP:
        return self.mcp


# Create and export the server
mcp_server = CodeGraphMCPServer()
mcp = mcp_server.get_server()


if __name__ == "__main__":
    logger.info("Starting Code Graph MCP Server")
    mcp.run("stdio")
