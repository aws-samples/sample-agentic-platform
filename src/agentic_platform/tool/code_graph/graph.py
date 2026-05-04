"""
GraphStore abstraction for the code ontology graph.

Current backend: NetworkX (in-memory, zero setup, good for single-repo dev workflows).

The GraphStore interface is designed to be swappable — see the scale path in the
MCP server README for future backend options.
"""

import logging
from abc import ABC, abstractmethod
from collections import deque
from typing import Optional

logger = logging.getLogger(__name__)


class GraphStore(ABC):
    """Abstract graph store interface. Implement this to swap backends."""

    @abstractmethod
    def load(self, nodes: list, edges: list) -> None:
        """Load nodes and edges into the store."""

    @abstractmethod
    def find_callers(self, function_name: str) -> list[dict]:
        """Return all nodes that call the given function name."""

    @abstractmethod
    def find_dependencies(self, node_name: str) -> list[dict]:
        """Return all nodes that the given node imports or calls."""

    @abstractmethod
    def find_importers(self, module_name: str) -> list[dict]:
        """Return all nodes that import the given module."""

    @abstractmethod
    def find_node(self, name: str) -> Optional[dict]:
        """Find a node by name."""

    @abstractmethod
    def remove_file(self, file_path: str) -> None:
        """Remove all nodes and edges for a file (used for incremental updates)."""

    @abstractmethod
    def find_branches(self, scope: str) -> Optional[dict]:
        """Return branch metadata for a function/method by its dotted scope name."""

    @abstractmethod
    def get_node_data(self, node_id: str) -> Optional[dict]:
        """Return node attributes by ID, or None if not found."""

    @abstractmethod
    def out_edges(self, node_id: str, edge_types: Optional[set[str]] = None) -> list[tuple[str, dict]]:
        """Return outgoing edges as (target_id, edge_data) pairs, optionally filtered by edge type."""

    @abstractmethod
    def node_count(self) -> int:
        """Return total number of nodes in the graph."""

    @abstractmethod
    def edge_count(self) -> int:
        """Return total number of edges in the graph."""


class NetworkXGraphStore(GraphStore):
    """
    In-memory graph store backed by NetworkX.
    Fast, zero-setup, suitable for single-repo local dev workflows.
    Holds the full graph in memory — practical up to ~100k nodes.
    """

    def __init__(self):
        try:
            import networkx as nx
            self._nx = nx
        except ImportError:
            raise ImportError("networkx is required: pip install networkx")

        self._graph = self._nx.MultiDiGraph()
        # Name index: name -> list of node ids (multiple nodes can share a name)
        self._name_index: dict[str, list[str]] = {}

    def load(self, nodes: list, edges: list) -> None:
        """Load parsed nodes and edges into the NetworkX graph."""
        for node in nodes:
            self._graph.add_node(
                node.id,
                name=node.name,
                node_type=node.node_type,
                file=node.file,
                line=node.line,
                language=node.language,
                metadata=node.metadata,
            )
            self._name_index.setdefault(node.name, []).append(node.id)

        # Build dotted Class.method entries in the index using a pre-indexed
        # edge lookup — O(classes × edges_per_class) instead of O(n² × e).
        edges_by_source: dict[str, list] = {}
        for edge in edges:
            edges_by_source.setdefault(edge.source_id, []).append(edge)

        for node in nodes:
            if node.node_type == "Class":
                for edge in edges_by_source.get(node.id, []):
                    if edge.edge_type == "DEFINES":
                        dotted = f"{node.name}.{edge.target_name}"
                        # Find the child node ID — must be in the same file
                        # and scoped under this class (ID contains "ClassName.method")
                        child_ids = self._name_index.get(edge.target_name, [])
                        expected_scope = f"{node.name}.{edge.target_name}"
                        for cid in child_ids:
                            cid_scope = cid.split("::", 1)[1].rsplit("::", 1)[0]
                            if (cid_scope == expected_scope
                                    and self._graph.nodes.get(cid, {}).get("file") == node.file):
                                ids = self._name_index.setdefault(dotted, [])
                                if cid not in ids:
                                    ids.append(cid)
                                break

        resolved = 0
        unresolved = 0
        seen_edges: set[tuple[str, str, str]] = set()
        for edge in edges:
            source_id = edge.source_id
            # Resolve target name to node id(s)
            target_ids = self._name_index.get(edge.target_name, [])

            # For DEFINES edges, restrict to targets in the same file
            # to prevent fan-out (e.g. every __init__ in the codebase)
            if edge.edge_type == "DEFINES" and target_ids:
                source_file = self._graph.nodes[source_id].get("file", "")
                target_ids = [
                    tid for tid in target_ids
                    if self._graph.nodes.get(tid, {}).get("file", "") == source_file
                ]

            if target_ids:
                for target_id in target_ids:
                    key = (source_id, target_id, edge.edge_type)
                    if key in seen_edges:
                        continue
                    seen_edges.add(key)
                    self._graph.add_edge(
                        source_id,
                        target_id,
                        edge_type=edge.edge_type,
                        file=edge.file,
                        line=edge.line,
                    )
                resolved += 1
            else:
                # Store as unresolved external reference
                ext_id = f"external::{edge.target_name}"
                if ext_id not in self._graph:
                    self._graph.add_node(ext_id, name=edge.target_name, node_type="External",
                                         file="", line=0, language="unknown")
                key = (source_id, ext_id, edge.edge_type)
                if key not in seen_edges:
                    seen_edges.add(key)
                    self._graph.add_edge(
                        source_id, ext_id,
                        edge_type=edge.edge_type,
                        file=edge.file,
                        line=edge.line,
                    )
                unresolved += 1

        logger.info("Graph loaded: %d nodes, %d edges (%d resolved, %d external)",
                    self._graph.number_of_nodes(), self._graph.number_of_edges(),
                    resolved, unresolved)

    def find_callers(self, function_name: str) -> list[dict]:
        """Return all nodes that CALL the given function name."""
        target_ids = self._name_index.get(function_name, [])
        results = []
        for target_id in target_ids:
            for src, _, data in self._graph.in_edges(target_id, data=True):
                if data.get("edge_type") == "CALLS":
                    node_data = self._graph.nodes[src]
                    results.append({
                        "name": node_data.get("name"),
                        "file": node_data.get("file"),
                        "line": data.get("line"),
                        "node_type": node_data.get("node_type"),
                    })
        return results

    def find_dependencies(self, node_name: str) -> list[dict]:
        """Return all nodes that the given node imports or calls (outgoing edges).

        For Class/Method nodes, also walks up to the containing module to include
        module-level imports — since Python imports are declared at the module level,
        not on the class itself.
        """
        source_ids = self._name_index.get(node_name, [])
        results = []
        seen = set()

        def collect(node_id: str) -> None:
            for _, tgt, data in self._graph.out_edges(node_id, data=True):
                edge_type = data.get("edge_type")
                if edge_type == "DEFINES":
                    continue  # skip — these are children, not dependencies
                if tgt not in seen:
                    seen.add(tgt)
                    node_data = self._graph.nodes[tgt]
                    results.append({
                        "name": node_data.get("name"),
                        "file": node_data.get("file"),
                        "line": data.get("line"),
                        "edge_type": edge_type,
                        "node_type": node_data.get("node_type"),
                    })

        for source_id in source_ids:
            node_data = self._graph.nodes[source_id]
            collect(source_id)

            # If this is a Class or Method, also pull in the containing module's imports
            if node_data.get("node_type") in ("Class", "Method", "Function"):
                file_path = node_data.get("file")
                if file_path:
                    module_id = f"{file_path}::module"
                    if module_id in self._graph and module_id not in seen:
                        collect(module_id)

        return results

    def find_importers(self, module_name: str) -> list[dict]:
        """Return all nodes that import the given module."""
        target_ids = list(self._name_index.get(module_name, []))
        # Check external nodes — match exact key or any qualified path ending with the module name
        # e.g. "memory_models" matches "external::agentic_platform.core.models.memory_models"
        suffix = f".{module_name}"
        existing = set(target_ids)
        for node_id in self._graph.nodes:
            if not node_id.startswith("external::"):
                continue
            key = node_id[len("external::"):]
            if (key == module_name or key.endswith(suffix)) and node_id not in existing:
                target_ids.append(node_id)
                existing.add(node_id)

        results = []
        for target_id in target_ids:
            for src, _, data in self._graph.in_edges(target_id, data=True):
                if data.get("edge_type") == "IMPORTS":
                    node_data = self._graph.nodes[src]
                    results.append({
                        "name": node_data.get("name"),
                        "file": node_data.get("file"),
                        "line": data.get("line"),
                        "node_type": node_data.get("node_type"),
                    })
        return results

    def find_node(self, name: str) -> Optional[dict]:
        """Find the first node matching the given name."""
        ids = self._name_index.get(name, [])
        if not ids:
            return None
        data = self._graph.nodes[ids[0]]
        return {"id": ids[0], **data}

    def find_branches(self, scope: str) -> Optional[dict]:
        """
        Return branch metadata for a function/method by name or dotted scope.

        scope can be:
          - a bare function name:  "invoke"
          - a dotted scope:        "StrandsJiraAgent.invoke"

        Returns the first matching node's branch data, or None if not found
        or the node has no branch metadata.
        """
        # Try exact dotted lookup first (e.g. "StrandsJiraAgent.invoke")
        candidate_ids = self._name_index.get(scope, [])

        # Dotted scope didn't match the index — try resolving via
        # the class's DEFINES edges as a last resort
        if not candidate_ids and "." in scope:
            parts = scope.rsplit(".", 1)
            class_name, method_name = parts[0], parts[1]
            class_ids = self._name_index.get(class_name, [])
            for class_id in class_ids:
                for _, child_id, data in self._graph.out_edges(class_id, data=True):
                    if (data.get("edge_type") == "DEFINES"
                            and self._graph.nodes[child_id].get("name") == method_name):
                        candidate_ids = [child_id]
                        break
                if candidate_ids:
                    break

        # Collect candidates that have branch data
        for nid in candidate_ids:
            node_data = self._graph.nodes[nid]
            branches = node_data.get("metadata", {}).get("branches", [])
            # Also collect branches from nested functions (DEFINES children, recursive)
            nested_branches = []
            queue = deque([nid])
            visited = {nid}
            while queue:
                current = queue.popleft()
                for _, child_id, data in self._graph.out_edges(current, data=True):
                    if data.get("edge_type") == "DEFINES" and child_id not in visited:
                        visited.add(child_id)
                        child_data = self._graph.nodes[child_id]
                        child_branches = child_data.get("metadata", {}).get("branches")
                        if child_branches:
                            nested_branches.extend(child_branches)
                        queue.append(child_id)
            all_branches = branches + nested_branches
            if all_branches:
                complexity = (
                    sum(
                        sum(1 for a in b["arms"]
                            if a["kind"] in ("if", "elif", "except", "catch", "case"))
                        for b in all_branches
                    ) + 1
                )
                return {
                    "scope": scope,
                    "file": node_data.get("file"),
                    "line": node_data.get("line"),
                    "language": node_data.get("language"),
                    "cyclomatic_complexity": complexity,
                    "total_branches": len(all_branches),
                    "branches": all_branches,
                }

        return None

    def get_node_data(self, node_id: str) -> Optional[dict]:
        """Return node attributes by ID, or None if not found."""
        if node_id not in self._graph:
            return None
        return dict(self._graph.nodes[node_id])

    def out_edges(self, node_id: str, edge_types: Optional[set[str]] = None) -> list[tuple[str, dict]]:
        """Return outgoing edges as (target_id, edge_data) pairs."""
        if node_id not in self._graph:
            return []
        results = []
        for _, target, data in self._graph.out_edges(node_id, data=True):
            if edge_types is None or data.get("edge_type") in edge_types:
                results.append((target, dict(data)))
        return results

    def remove_file(self, file_path: str) -> None:
        """Remove all nodes and edges associated with a file (for incremental updates)."""
        nodes_to_remove = [
            n for n, d in self._graph.nodes(data=True)
            if d.get("file") == file_path
        ]
        for node_id in nodes_to_remove:
            # Clean up name index (bare name and any dotted entries)
            name = self._graph.nodes[node_id].get("name")
            if name and name in self._name_index:
                self._name_index[name] = [
                    nid for nid in self._name_index[name] if nid != node_id
                ]
                if not self._name_index[name]:
                    del self._name_index[name]
            # Also clean dotted entries (e.g. "ClassName.method")
            to_delete = []
            for key, ids in self._name_index.items():
                if node_id in ids:
                    ids.remove(node_id)
                    if not ids:
                        to_delete.append(key)
            for key in to_delete:
                del self._name_index[key]
            self._graph.remove_node(node_id)
        logger.info("Removed %d nodes for file: %s", len(nodes_to_remove), file_path)

    def node_count(self) -> int:
        return self._graph.number_of_nodes()

    def edge_count(self) -> int:
        return self._graph.number_of_edges()


def create_graph_store() -> GraphStore:
    """Factory that returns the graph store. Currently only NetworkX is supported."""
    return NetworkXGraphStore()
