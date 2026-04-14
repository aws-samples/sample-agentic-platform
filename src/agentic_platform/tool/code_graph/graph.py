"""
GraphStore abstraction for the code ontology graph.

Current backend: NetworkX (in-memory, zero setup, good for single-repo dev workflows).

The GraphStore interface is designed to be swappable — see the scale path in the
MCP server README for future backend options.
"""

import logging
from abc import ABC, abstractmethod
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
                **node.metadata,
            )
            self._name_index.setdefault(node.name, []).append(node.id)

        resolved = 0
        unresolved = 0
        for edge in edges:
            source_id = edge.source_id
            # Resolve target name to node id(s)
            target_ids = self._name_index.get(edge.target_name, [])
            if target_ids:
                for target_id in target_ids:
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

    def remove_file(self, file_path: str) -> None:
        """Remove all nodes and edges associated with a file (for incremental updates)."""
        nodes_to_remove = [
            n for n, d in self._graph.nodes(data=True)
            if d.get("file") == file_path
        ]
        for node_id in nodes_to_remove:
            # Clean up name index
            name = self._graph.nodes[node_id].get("name")
            if name and name in self._name_index:
                self._name_index[name] = [
                    nid for nid in self._name_index[name] if nid != node_id
                ]
                if not self._name_index[name]:
                    del self._name_index[name]
            self._graph.remove_node(node_id)
        logger.info("Removed %d nodes for file: %s", len(nodes_to_remove), file_path)

    def node_count(self) -> int:
        return self._graph.number_of_nodes()

    def edge_count(self) -> int:
        return self._graph.number_of_edges()


def create_graph_store() -> GraphStore:
    """Factory that returns the graph store. Currently only NetworkX is supported."""
    return NetworkXGraphStore()
