"""
Query tools for the code ontology graph.

These are the tools exposed to the LLM agent (and via MCP to Kiro).
Uses a hybrid strategy:
  - Template queries for common patterns (reliable, fast)
  - Free-form fallback via the LLM generating a query from the graph schema

Template tools:
  - find_callers       — who calls this function?
  - find_dependencies  — what does this module/class depend on?
  - find_importers     — what files import this module?
  - trace_impact       — what would be affected if this node changed?

Free-form fallback is handled in the MCP server layer by passing graph schema
context to the LLM and letting it synthesize an answer from template results.
"""

import logging
from .graph import GraphStore

logger = logging.getLogger(__name__)


def find_callers(graph: GraphStore, function_name: str) -> dict:
    """
    Find all callers of a given function across the codebase.

    Use this to answer: "If I rename X, what files need updating?"

    Args:
        graph: The loaded graph store
        function_name: Name of the function to find callers for

    Returns:
        Dict with callers list and summary
    """
    callers = graph.find_callers(function_name)

    if not callers:
        return {
            "function": function_name,
            "caller_count": 0,
            "callers": [],
            "summary": f"No callers found for '{function_name}'. It may be unused or only called externally.",
        }

    # Deduplicate by file
    files = sorted(set(c["file"] for c in callers if c.get("file")))

    return {
        "function": function_name,
        "caller_count": len(callers),
        "affected_files": files,
        "callers": callers,
        "summary": (
            f"'{function_name}' is called {len(callers)} time(s) across {len(files)} file(s). "
            f"Renaming or deleting it would require updates in: {', '.join(files)}"
        ),
    }


def find_dependencies(graph: GraphStore, node_name: str) -> dict:
    """
    Find everything a given module, class, or function depends on.

    Use this to answer: "What does X depend on?" or "What would I need to
    understand before modifying X?"

    Args:
        graph: The loaded graph store
        node_name: Name of the node to find dependencies for

    Returns:
        Dict with dependencies grouped by edge type
    """
    deps = graph.find_dependencies(node_name)

    if not deps:
        node = graph.find_node(node_name)
        if not node:
            return {
                "node": node_name,
                "found": False,
                "summary": f"'{node_name}' was not found in the graph.",
            }
        return {
            "node": node_name,
            "found": True,
            "dependency_count": 0,
            "dependencies": [],
            "summary": f"'{node_name}' has no outgoing dependencies in the graph.",
        }

    # Group by edge type
    grouped: dict[str, list] = {}
    for dep in deps:
        edge_type = dep.get("edge_type", "UNKNOWN")
        grouped.setdefault(edge_type, []).append(dep)

    return {
        "node": node_name,
        "found": True,
        "dependency_count": len(deps),
        "by_type": grouped,
        "summary": (
            f"'{node_name}' has {len(deps)} dependencies: "
            + ", ".join(f"{len(v)} {k}" for k, v in grouped.items())
        ),
    }


def find_importers(graph: GraphStore, module_name: str) -> dict:
    """
    Find all files that import a given module.

    Use this to answer: "What breaks if I remove or rename this module?"

    Args:
        graph: The loaded graph store
        module_name: Name of the module to find importers for

    Returns:
        Dict with importers list and affected files
    """
    importers = graph.find_importers(module_name)

    if not importers:
        return {
            "module": module_name,
            "importer_count": 0,
            "importers": [],
            "summary": f"No files import '{module_name}'.",
        }

    files = sorted(set(i["file"] for i in importers if i.get("file")))

    return {
        "module": module_name,
        "importer_count": len(importers),
        "affected_files": files,
        "importers": importers,
        "summary": (
            f"'{module_name}' is imported by {len(importers)} location(s) in {len(files)} file(s): "
            f"{', '.join(files)}"
        ),
    }


def trace_impact(graph: GraphStore, node_name: str) -> dict:
    """
    Trace the full impact of changing or deleting a node.

    Combines callers + importers to give a complete picture of what
    would be affected. Use this to answer: "What breaks if I change X?"

    Args:
        graph: The loaded graph store
        node_name: Name of the node to trace impact for

    Returns:
        Dict with combined impact analysis
    """
    node = graph.find_node(node_name)

    if not node:
        return {
            "node": node_name,
            "found": False,
            "summary": f"'{node_name}' was not found in the graph.",
        }

    callers_result = find_callers(graph, node_name)
    importers_result = find_importers(graph, node_name)

    all_affected_files = sorted(set(
        callers_result.get("affected_files", []) +
        importers_result.get("affected_files", [])
    ))

    total_references = (
        callers_result.get("caller_count", 0) +
        importers_result.get("importer_count", 0)
    )

    return {
        "node": node_name,
        "found": True,
        "node_info": node,
        "total_references": total_references,
        "affected_files": all_affected_files,
        "callers": callers_result.get("callers", []),
        "importers": importers_result.get("importers", []),
        "summary": (
            f"Changing '{node_name}' would impact {total_references} reference(s) "
            f"across {len(all_affected_files)} file(s): {', '.join(all_affected_files)}"
            if all_affected_files
            else f"'{node_name}' has no known references — safe to change or delete."
        ),
    }


def get_graph_stats(graph: GraphStore) -> dict:
    """Return basic stats about the loaded graph."""
    return {
        "node_count": graph.node_count(),
        "edge_count": graph.edge_count(),
        "summary": f"Graph contains {graph.node_count()} nodes and {graph.edge_count()} edges.",
    }
