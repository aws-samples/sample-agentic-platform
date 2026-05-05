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
from collections import deque
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


def get_branches(graph: GraphStore, scope: str) -> dict:
    """
    Return branch data for a function or method from the graph.

    Branch data is extracted at graph build time and stored as node metadata,
    so this is a pure graph lookup — no file I/O or re-parsing.

    Args:
        graph: The loaded graph store
        scope: Function or method name, optionally dotted: "MyClass.my_method"

    Returns:
        Dict with branches, cyclomatic_complexity, and summary
    """
    result = graph.find_branches(scope)

    if not result:
        return {
            "scope": scope,
            "found": False,
            "summary": (
                f"No branch data found for '{scope}'. "
                "The function may not exist, have no branches, or the graph "
                "may need to be rebuilt with 'rebuild_graph'."
            ),
        }

    branches = result["branches"]
    complexity = result["cyclomatic_complexity"]

    by_type: dict[str, int] = {}
    for b in branches:
        by_type[b["branch_type"]] = by_type.get(b["branch_type"], 0) + 1
    type_summary = ", ".join(f"{count} {t}" for t, count in sorted(by_type.items()))

    return {
        "scope": scope,
        "found": True,
        "file": result["file"],
        "line": result["line"],
        "language": result["language"],
        "total_branches": len(branches),
        "cyclomatic_complexity": complexity,
        "branches": branches,
        "summary": (
            f"'{scope}' has {len(branches)} branch point(s) "
            f"(cyclomatic complexity: {complexity})"
            + (f" — {type_summary}" if type_summary else "")
        ),
    }


def walk_branches(graph: GraphStore, entry_point: str) -> dict:
    """
    Walk the call graph from an entry point via BFS and collect all branch
    metadata across every reachable function.

    Use cases:
      - Test planning: map every conditional path that tests should cover
      - Migration scoping: understand the full complexity of a subsystem
        before and after conversion
      - Complexity audit: find total cyclomatic complexity reachable from
        an entry point
      - Code review: see all conditional logic in a feature's call chain

    Args:
        graph: The loaded graph store
        entry_point: Module, class, or function name to start from
                     (e.g. "jira_agent", "StrandsJiraAgent", "server")

    Returns:
        Dict with entry_point, functions with branches, total branch count,
        and a per-function breakdown.
    """
    # Find the entry point node(s)
    node = graph.find_node(entry_point)
    if not node:
        return {
            "entry_point": entry_point,
            "found": False,
            "summary": f"'{entry_point}' was not found in the graph.",
        }

    # Collect all reachable internal functions via BFS on CALLS/DEFINES/IMPORTS edges
    WALK_EDGE_TYPES = {"CALLS", "DEFINES", "IMPORTS"}
    visited: set[str] = set()
    queue = deque([node["id"]])
    function_nodes: list[dict] = []

    while queue:
        nid = queue.popleft()
        if nid in visited:
            continue
        visited.add(nid)

        nd = graph.get_node_data(nid)
        if not nd:
            continue

        # Skip external nodes
        if nid.startswith("external::"):
            continue

        # Collect this node if it's a function/method/class
        if nd.get("node_type") in ("Function", "Method", "Class", "Module"):
            function_nodes.append({"id": nid, **nd})

        # Walk outgoing CALLS, DEFINES, and IMPORTS edges
        for child_id, data in graph.out_edges(nid, WALK_EDGE_TYPES):
            if child_id not in visited:
                queue.append(child_id)

    # For each function node, collect branch data
    functions_with_branches = []
    total_branches = 0
    total_complexity = 0

    for fn in function_nodes:
        if fn.get("node_type") not in ("Function", "Method"):
            continue
        # Extract scoped name from node ID: "file::MyClass.invoke::Function" → "MyClass.invoke"
        fn_scope = fn["id"].split("::", 1)[1].rsplit("::", 1)[0]
        branch_result = graph.find_branches(fn_scope)
        if branch_result:
            entry = {
                "name": fn["name"],
                "file": fn.get("file", ""),
                "line": fn.get("line", 0),
                "total_branches": branch_result["total_branches"],
                "cyclomatic_complexity": branch_result["cyclomatic_complexity"],
                "branches": branch_result["branches"],
            }
            functions_with_branches.append(entry)
            total_branches += branch_result["total_branches"]
            total_complexity += branch_result["cyclomatic_complexity"]

    # Deduplicate by file+name (same function reached via multiple paths)
    seen = set()
    deduped = []
    for fn in functions_with_branches:
        key = (fn["file"], fn["name"], fn["line"])
        if key not in seen:
            seen.add(key)
            deduped.append(fn)
    functions_with_branches = deduped

    # Recalculate totals after dedup
    total_branches = sum(f["total_branches"] for f in functions_with_branches)
    total_complexity = sum(f["cyclomatic_complexity"] for f in functions_with_branches)

    # P2: Diagnostics when walk finds 0 functions with branches
    diagnostic = None
    if not functions_with_branches:
        raw_edges = graph.out_edges(node["id"])
        edge_counts = {}
        internal_targets = []
        for target_id, data in raw_edges:
            et = data.get("edge_type")
            edge_counts[et] = edge_counts.get(et, 0) + 1
            nd = graph.get_node_data(target_id)
            tname = nd.get("name", target_id) if nd else target_id
            if et in WALK_EDGE_TYPES and not target_id.startswith("external::"):
                internal_targets.append(tname)
        diagnostic = (
            f"Entry point '{entry_point}' has {len(raw_edges)} outgoing edge(s) "
            f"(types: {edge_counts}) but walk reached 0 functions with branches. "
            f"Internal targets reachable: {internal_targets[:10]}. "
            f"Nodes visited: {len(visited)}. "
            "If this is unexpected, try rebuilding the graph or using file_path fallback."
        )

    # P3: Flag decorated functions (e.g. @tool, @app.post) in output
    for fn in functions_with_branches:
        fn_node_id = None
        for fnode in function_nodes:
            if fnode.get("name") == fn["name"] and fnode.get("file") == fn["file"]:
                fn_node_id = fnode.get("id")
                break
        if fn_node_id:
            nd = graph.get_node_data(fn_node_id)
            decorators = (nd or {}).get("metadata", {}).get("decorators", [])
            if decorators:
                fn["decorators"] = decorators

    result = {
        "entry_point": entry_point,
        "found": True,
        "entry_file": node.get("file", ""),
        "functions_analyzed": len(functions_with_branches),
        "total_branches": total_branches,
        "total_cyclomatic_complexity": total_complexity,
        "functions": functions_with_branches,
        "summary": (
            f"Walk from '{entry_point}': {len(functions_with_branches)} function(s) "
            f"with {total_branches} branch point(s), total cyclomatic complexity {total_complexity}."
        ),
    }
    if diagnostic:
        result["diagnostic"] = diagnostic
    return result
