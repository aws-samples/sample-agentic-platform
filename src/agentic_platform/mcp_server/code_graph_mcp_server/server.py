"""
Code Graph MCP Server.

Parses a local codebase into a code ontology graph and exposes graph query
tools via the MCP protocol. Designed to run locally alongside a developer's
workspace — source code never leaves the machine.

Integrates with Kiro (and any MCP-compatible client) to answer questions like:
  - "If I rename generate_embedding(), what files need updating?"
  - "What does AuthService depend on?"
  - "What would break if I delete this class?"

Transport: stdio (for Kiro/IDE MCP integration)

Usage:
  python -m agentic_platform.mcp_server.code_graph_mcp_server.server
"""

import ast
import json
import logging
import os
from mcp.server.fastmcp import FastMCP
from agentic_platform.tool.code_graph.cache import is_cache_valid, load_cache, save_cache, invalidate_cache
from agentic_platform.tool.code_graph.parser import parse_directory, parse_file
from agentic_platform.tool.code_graph.graph import create_graph_store
from agentic_platform.tool.code_graph import query_tools

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


class CodeGraphMCPServer:
    """MCP server that exposes code ontology graph query tools."""

    def __init__(self, name: str = "code-graph"):
        self.mcp = FastMCP(name)
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
        def find_callers(function_name: str) -> dict:
            """
            Find all callers of a function across the codebase.

            Use this to answer: "If I rename or delete X, what files need updating?"
            Returns each call site with file path and line number.

            Args:
                function_name: The name of the function to find callers for
            """
            return query_tools.find_callers(self._get_graph(), function_name)

        @self.mcp.tool()
        def find_dependencies(node_name: str) -> dict:
            """
            Find everything a module, class, or function depends on.

            Use this to answer: "What does X depend on?" or "What do I need to
            understand before modifying X?"
            Returns dependencies grouped by relationship type (CALLS, IMPORTS, etc.)

            Args:
                node_name: The name of the module, class, or function
            """
            return query_tools.find_dependencies(self._get_graph(), node_name)

        @self.mcp.tool()
        def find_importers(module_name: str) -> dict:
            """
            Find all files that import a given module.

            Use this to answer: "What breaks if I remove or rename this module?"
            Returns each import site with file path and line number.

            Args:
                module_name: The name of the module to find importers for
            """
            return query_tools.find_importers(self._get_graph(), module_name)

        @self.mcp.tool()
        def trace_impact(node_name: str) -> dict:
            """
            Trace the full impact of changing or deleting a node.

            Use this to answer: "What breaks if I change X?"
            Combines callers and importers for a complete impact picture.

            Args:
                node_name: The name of the function, class, or module to analyze
            """
            return query_tools.trace_impact(self._get_graph(), node_name)

        @self.mcp.tool()
        def graph_stats() -> dict:
            """
            Return stats about the loaded code graph.
            Useful for confirming the graph was built successfully.
            """
            return query_tools.get_graph_stats(self._get_graph())

        @self.mcp.tool()
        def update_file(file_path: str) -> dict:
            """
            Incrementally update the graph for a single changed file.

            Removes all existing nodes/edges for the file, re-parses it,
            and loads the fresh data. Much faster than a full rebuild.
            Called automatically by the Kiro fileEdited hook.

            Args:
                file_path: Absolute or relative path to the changed file
            """
            graph = self._get_graph()

            # Resolve to absolute path
            if not os.path.isabs(file_path):
                repo_path = os.getenv("REPO_PATH", ".")
                file_path = os.path.join(repo_path, file_path)

            if not os.path.exists(file_path):
                return {"status": "skipped", "reason": f"File not found: {file_path}"}

            # Remove stale nodes for this file, re-parse, reload
            graph.remove_file(file_path)
            result = parse_file(file_path)
            graph.load(result.nodes, result.edges)

            # Rebuilding a minimal ParseResult snapshot isn't practical here,
            # so invalidate the cache so the next restart does a clean rebuild.
            repo_path = os.getenv("REPO_PATH", ".")
            invalidate_cache(repo_path)

            return {
                "status": "updated",
                "file": file_path,
                "nodes_added": len(result.nodes),
                "edges_added": len(result.edges),
                **query_tools.get_graph_stats(graph),
            }

        @self.mcp.tool()
        def run_query(code: str) -> dict:
            """
            Run a custom Python query against the code graph.

            The graph is exposed as `G` (a NetworkX MultiDiGraph) and `idx`
            (the name index: dict[str, list[node_id]]).

            Node attributes: name, node_type, file, line, language
            Edge attributes: edge_type ("CALLS" | "IMPORTS" | "INHERITS"), file, line
            node_type values: "Function", "Class", "Module", "External"

            Your code must assign the result to a variable named `result`.

            Available in scope: G, idx, collections, itertools

            Examples
            --------
            # Top 10 most-called functions (excluding builtins/externals)
            counts = collections.Counter()
            for u, v, d in G.edges(data=True):
                if d["edge_type"] == "CALLS" and not v.startswith("external::"):
                    counts[G.nodes[v].get("name")] += 1
            result = counts.most_common(10)

            # All classes that inherit from BaseModel
            result = [
                (G.nodes[v].get("name"), G.nodes[v].get("file"))
                for u, v, d in G.edges(data=True)
                if d["edge_type"] == "INHERITS" and G.nodes[u].get("name") == "BaseModel"
            ]

            Args:
                code: Python code to execute. Must assign output to `result`.
            """
            import collections as _collections
            import itertools as _itertools

            valid, reason = self._validate_query(code)
            if not valid:
                return {"error": reason}

            graph = self._get_graph()
            local_ns = {
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
        def rebuild_graph(repo_path: str = "") -> dict:
            """
            Rebuild the code graph from the given repo path (or REPO_PATH env var).
            Use this after significant code changes to refresh the graph.

            Args:
                repo_path: Optional path to the repo root. Defaults to REPO_PATH env var.
            """
            if repo_path:
                os.environ["REPO_PATH"] = repo_path
            self._graph = None  # force rebuild on next query
            graph = self._get_graph()  # rebuilds and saves cache automatically
            return {
                "status": "rebuilt",
                "repo_path": os.getenv("REPO_PATH", "."),
                **query_tools.get_graph_stats(graph),
            }

    def get_server(self) -> FastMCP:
        return self.mcp


# Create and export the server
mcp_server = CodeGraphMCPServer()
mcp = mcp_server.get_server()


if __name__ == "__main__":
    logger.info("Starting Code Graph MCP Server")
    mcp.run("stdio")
