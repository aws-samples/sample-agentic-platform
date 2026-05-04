"""
Polyglot code parser using tree-sitter.

Supports Python, TypeScript, Java, and Terraform (HCL) via per-language adapters.

Each adapter is a thin layer (~20-30 lines) that maps tree-sitter AST node types
to our canonical graph model. Adding a new language = adding a new adapter.

Branch data is extracted in the same parse pass and stored as metadata on
Function/Method nodes, so the graph build is a single tree-sitter walk per file.

Scale note: For very large repos, this module can be parallelized by directory/module.
At AWS scale, consider running this as a Lambda or Fargate task triggered by S3 events.
"""

import logging
from dataclasses import dataclass, field
from pathlib import Path
from typing import Optional

logger = logging.getLogger(__name__)

# Language detection by file extension
EXTENSION_TO_LANGUAGE = {
    ".py": "python",
    ".ts": "typescript",
    ".tsx": "typescript",
    ".js": "javascript",
    ".jsx": "javascript",
    ".java": "java",
    ".tf": "terraform",
    ".hcl": "terraform",
}


@dataclass
class GraphNode:
    """A node in the code ontology graph."""
    id: str           # unique: file::name::type
    name: str
    node_type: str    # Function, Class, Method, Module, Variable
    file: str
    line: int
    language: str
    metadata: dict = field(default_factory=dict)


@dataclass
class GraphEdge:
    """A directed edge in the code ontology graph."""
    source_id: str
    target_name: str  # resolved to target_id during graph load
    edge_type: str    # CALLS, IMPORTS, INHERITS, DEFINES, READS, WRITES
    file: str
    line: int


@dataclass
class ParseResult:
    nodes: list[GraphNode] = field(default_factory=list)
    edges: list[GraphEdge] = field(default_factory=list)


def _parse_python(source: str, file_path: str) -> ParseResult:
    """Extract nodes and edges from a Python source file."""
    try:
        import tree_sitter_python as tspython
        from tree_sitter import Language, Parser

        PY_LANGUAGE = Language(tspython.language())
        parser = Parser(PY_LANGUAGE)
    except ImportError:
        logger.warning("tree-sitter-python not installed, skipping %s", file_path)
        return ParseResult()

    result = ParseResult()
    tree = parser.parse(source.encode())
    root = tree.root_node

    # Module node
    module_id = f"{file_path}::module"
    result.nodes.append(GraphNode(
        id=module_id,
        name=Path(file_path).stem,
        node_type="Module",
        file=file_path,
        line=0,
        language="python",
    ))

    def walk(node, parent_id: Optional[str] = None):
        if node.type == "import_statement" or node.type == "import_from_statement":
            # Extract import edges
            for child in node.children:
                if child.type in ("dotted_name", "aliased_import"):
                    name = source[child.start_byte:child.end_byte].split(" as ")[0].strip()
                    result.edges.append(GraphEdge(
                        source_id=parent_id or module_id,
                        target_name=name,
                        edge_type="IMPORTS",
                        file=file_path,
                        line=node.start_point[0] + 1,
                    ))

        elif node.type == "function_definition":
            name_node = node.child_by_field_name("name")
            if name_node:
                name = source[name_node.start_byte:name_node.end_byte]
                node_id = f"{file_path}::{name}::Function"
                # Capture decorators from parent decorated_definition
                decorators = []
                if node.parent and node.parent.type == "decorated_definition":
                    for sib in node.parent.children:
                        if sib.type == "decorator":
                            decorators.append(source[sib.start_byte:sib.end_byte].lstrip("@").strip())
                result.nodes.append(GraphNode(
                    id=node_id,
                    name=name,
                    node_type="Function" if parent_id == module_id else "Method",
                    file=file_path,
                    line=node.start_point[0] + 1,
                    language="python",
                    metadata={"decorators": decorators} if decorators else {},
                ))
                if parent_id:
                    result.edges.append(GraphEdge(
                        source_id=parent_id,
                        target_name=name,
                        edge_type="DEFINES",
                        file=file_path,
                        line=node.start_point[0] + 1,
                    ))
                for child in node.children:
                    walk(child, node_id)
                return  # already walked children

        elif node.type == "class_definition":
            name_node = node.child_by_field_name("name")
            if name_node:
                name = source[name_node.start_byte:name_node.end_byte]
                node_id = f"{file_path}::{name}::Class"
                result.nodes.append(GraphNode(
                    id=node_id,
                    name=name,
                    node_type="Class",
                    file=file_path,
                    line=node.start_point[0] + 1,
                    language="python",
                ))
                # DEFINES edge from parent (module or enclosing class) to this class
                if parent_id:
                    result.edges.append(GraphEdge(
                        source_id=parent_id,
                        target_name=name,
                        edge_type="DEFINES",
                        file=file_path,
                        line=node.start_point[0] + 1,
                    ))
                # Inheritance edges
                bases = node.child_by_field_name("superclasses")
                if bases:
                    for base in bases.children:
                        if base.type == "identifier":
                            base_name = source[base.start_byte:base.end_byte]
                            result.edges.append(GraphEdge(
                                source_id=node_id,
                                target_name=base_name,
                                edge_type="INHERITS",
                                file=file_path,
                                line=node.start_point[0] + 1,
                            ))
                for child in node.children:
                    walk(child, node_id)
                return

        elif node.type == "call":
            func_node = node.child_by_field_name("function")
            if func_node and parent_id:
                callee = source[func_node.start_byte:func_node.end_byte]
                line = node.start_point[0] + 1
                # Always record the full callee (e.g. "self.client.get_session_context")
                result.edges.append(GraphEdge(
                    source_id=parent_id,
                    target_name=callee,
                    edge_type="CALLS",
                    file=file_path,
                    line=line,
                ))
                # For attribute calls (a.b.c), also emit edges for:
                #   - the method name alone ("c") so find_callers("get_session_context") works
                #   - the root object name ("a") so find_callers("MemoryGatewayClient") works
                #     (skipping "self" and "cls" since they're not meaningful targets)
                if "." in callee:
                    parts = callee.split(".")
                    method_name = parts[-1]
                    root_name = parts[0]
                    if method_name != callee:
                        result.edges.append(GraphEdge(
                            source_id=parent_id,
                            target_name=method_name,
                            edge_type="CALLS",
                            file=file_path,
                            line=line,
                        ))
                    if root_name not in ("self", "cls") and root_name != callee:
                        result.edges.append(GraphEdge(
                            source_id=parent_id,
                            target_name=root_name,
                            edge_type="CALLS",
                            file=file_path,
                            line=line,
                        ))

        for child in node.children:
            walk(child, parent_id)

    walk(root, module_id)
    return result


def _parse_typescript(source: str, file_path: str) -> ParseResult:
    """Extract nodes and edges from a TypeScript/JavaScript source file."""
    try:
        import tree_sitter_typescript as tsts
        from tree_sitter import Language, Parser

        TS_LANGUAGE = Language(tsts.language_typescript())
        parser = Parser(TS_LANGUAGE)
    except ImportError:
        logger.warning("tree-sitter-typescript not installed, skipping %s", file_path)
        return ParseResult()

    result = ParseResult()
    tree = parser.parse(source.encode())
    root = tree.root_node

    module_id = f"{file_path}::module"
    result.nodes.append(GraphNode(
        id=module_id,
        name=Path(file_path).stem,
        node_type="Module",
        file=file_path,
        line=0,
        language="typescript",
    ))

    def walk(node, parent_id: Optional[str] = None):
        if node.type in ("import_statement", "import_declaration"):
            for child in node.children:
                if child.type == "string":
                    name = source[child.start_byte:child.end_byte].strip("'\"")
                    result.edges.append(GraphEdge(
                        source_id=parent_id or module_id,
                        target_name=name,
                        edge_type="IMPORTS",
                        file=file_path,
                        line=node.start_point[0] + 1,
                    ))

        elif node.type in ("function_declaration", "method_definition", "arrow_function"):
            name_node = node.child_by_field_name("name")
            if name_node:
                name = source[name_node.start_byte:name_node.end_byte]
                node_id = f"{file_path}::{name}::Function"
                result.nodes.append(GraphNode(
                    id=node_id,
                    name=name,
                    node_type="Function",
                    file=file_path,
                    line=node.start_point[0] + 1,
                    language="typescript",
                ))
                if parent_id:
                    result.edges.append(GraphEdge(
                        source_id=parent_id,
                        target_name=name,
                        edge_type="DEFINES",
                        file=file_path,
                        line=node.start_point[0] + 1,
                    ))
                for child in node.children:
                    walk(child, node_id)
                return

        elif node.type == "class_declaration":
            name_node = node.child_by_field_name("name")
            if name_node:
                name = source[name_node.start_byte:name_node.end_byte]
                node_id = f"{file_path}::{name}::Class"
                result.nodes.append(GraphNode(
                    id=node_id,
                    name=name,
                    node_type="Class",
                    file=file_path,
                    line=node.start_point[0] + 1,
                    language="typescript",
                ))
                for child in node.children:
                    walk(child, node_id)
                return

        elif node.type == "call_expression":
            func_node = node.child_by_field_name("function")
            if func_node and parent_id:
                callee = source[func_node.start_byte:func_node.end_byte]
                result.edges.append(GraphEdge(
                    source_id=parent_id,
                    target_name=callee,
                    edge_type="CALLS",
                    file=file_path,
                    line=node.start_point[0] + 1,
                ))

        for child in node.children:
            walk(child, parent_id)

    walk(root, module_id)
    return result


def _parse_java(source: str, file_path: str) -> ParseResult:
    """Extract nodes and edges from a Java source file."""
    try:
        import tree_sitter_java as tsjava
        from tree_sitter import Language, Parser

        JAVA_LANGUAGE = Language(tsjava.language())
        parser = Parser(JAVA_LANGUAGE)
    except ImportError:
        logger.warning("tree-sitter-java not installed, skipping %s", file_path)
        return ParseResult()

    result = ParseResult()
    tree = parser.parse(source.encode())
    root = tree.root_node

    module_id = f"{file_path}::module"
    result.nodes.append(GraphNode(
        id=module_id,
        name=Path(file_path).stem,
        node_type="Module",
        file=file_path,
        line=0,
        language="java",
    ))

    def walk(node, parent_id: Optional[str] = None):
        if node.type == "import_declaration":
            for child in node.children:
                if child.type == "scoped_identifier":
                    name = source[child.start_byte:child.end_byte]
                    result.edges.append(GraphEdge(
                        source_id=parent_id or module_id,
                        target_name=name,
                        edge_type="IMPORTS",
                        file=file_path,
                        line=node.start_point[0] + 1,
                    ))

        elif node.type == "class_declaration":
            name_node = node.child_by_field_name("name")
            if name_node:
                name = source[name_node.start_byte:name_node.end_byte]
                node_id = f"{file_path}::{name}::Class"
                result.nodes.append(GraphNode(
                    id=node_id,
                    name=name,
                    node_type="Class",
                    file=file_path,
                    line=node.start_point[0] + 1,
                    language="java",
                ))
                for child in node.children:
                    walk(child, node_id)
                return

        elif node.type == "method_declaration":
            name_node = node.child_by_field_name("name")
            if name_node:
                name = source[name_node.start_byte:name_node.end_byte]
                node_id = f"{file_path}::{name}::Method"
                result.nodes.append(GraphNode(
                    id=node_id,
                    name=name,
                    node_type="Method",
                    file=file_path,
                    line=node.start_point[0] + 1,
                    language="java",
                ))
                if parent_id:
                    result.edges.append(GraphEdge(
                        source_id=parent_id,
                        target_name=name,
                        edge_type="DEFINES",
                        file=file_path,
                        line=node.start_point[0] + 1,
                    ))
                for child in node.children:
                    walk(child, node_id)
                return

        elif node.type == "method_invocation":
            name_node = node.child_by_field_name("name")
            if name_node and parent_id:
                callee = source[name_node.start_byte:name_node.end_byte]
                result.edges.append(GraphEdge(
                    source_id=parent_id,
                    target_name=callee,
                    edge_type="CALLS",
                    file=file_path,
                    line=node.start_point[0] + 1,
                ))

        for child in node.children:
            walk(child, parent_id)

    walk(root, module_id)
    return result


def _parse_terraform(source: str, file_path: str) -> ParseResult:
    """Extract nodes and edges from a Terraform/HCL source file."""
    try:
        import tree_sitter_hcl as tshcl
        from tree_sitter import Language, Parser

        HCL_LANGUAGE = Language(tshcl.language())
        parser = Parser(HCL_LANGUAGE)
    except ImportError:
        logger.warning("tree-sitter-hcl not installed, skipping %s", file_path)
        return ParseResult()

    result = ParseResult()
    tree = parser.parse(source.encode())
    root = tree.root_node

    module_id = f"{file_path}::module"
    result.nodes.append(GraphNode(
        id=module_id,
        name=Path(file_path).stem,
        node_type="Module",
        file=file_path,
        line=0,
        language="terraform",
    ))

    def walk(node, parent_id: Optional[str] = None):
        # Terraform resources: resource "aws_s3_bucket" "my_bucket" { ... }
        if node.type == "block":
            children = node.children
            if len(children) >= 3:
                block_type = source[children[0].start_byte:children[0].end_byte]
                if block_type in ("resource", "module", "data"):
                    label_nodes = [c for c in children if c.type == "string_lit"]
                    if label_nodes:
                        name = source[label_nodes[-1].start_byte:label_nodes[-1].end_byte].strip('"')
                        node_id = f"{file_path}::{block_type}.{name}"
                        result.nodes.append(GraphNode(
                            id=node_id,
                            name=f"{block_type}.{name}",
                            node_type="Variable",
                            file=file_path,
                            line=node.start_point[0] + 1,
                            language="terraform",
                            metadata={"block_type": block_type},
                        ))

        for child in node.children:
            walk(child, parent_id)

    walk(root, module_id)
    return result


# Language adapter registry
# Scale note: register additional language adapters here as needed
_ADAPTERS = {
    "python": _parse_python,
    "typescript": _parse_typescript,
    "javascript": _parse_typescript,  # reuse TS adapter
    "java": _parse_java,
    "terraform": _parse_terraform,
}


def parse_file(file_path: str) -> ParseResult:
    """Parse a single source file into graph nodes and edges.

    Runs the branch extractor in the same call so branch data is stored
    as metadata on Function/Method nodes — no second tree-sitter pass needed.
    """
    from agentic_platform.tool.code_graph.branch_extractor import (
        extract_branches, branch_report_to_dict
    )

    path = Path(file_path)
    language = EXTENSION_TO_LANGUAGE.get(path.suffix.lower())

    if not language:
        logger.debug("Unsupported file type: %s", file_path)
        return ParseResult()

    adapter = _ADAPTERS.get(language)
    if not adapter:
        logger.debug("No adapter for language: %s", language)
        return ParseResult()

    try:
        source = path.read_text(encoding="utf-8", errors="ignore")
        result = adapter(source, str(file_path))
    except Exception as e:
        logger.warning("Failed to parse %s: %s", file_path, e)
        return ParseResult()

    # Extract branches and attach to the matching Function/Method nodes.
    # extract_branches re-uses the same tree-sitter grammar already loaded
    # by the adapter above, so the overhead is a second CST walk — one
    # file at a time, amortised across the full repo build.
    try:
        branch_report = extract_branches(file_path)
        if branch_report.branches:
            # Index branches by enclosing_scope for O(1) lookup
            by_scope: dict[str, list] = {}
            for b in branch_report_to_dict(branch_report)["branches"]:
                scope = b["enclosing_scope"]
                by_scope.setdefault(scope, []).append(b)

            for node in result.nodes:
                if node.node_type in ("Function", "Method"):
                    # Match on the last component of the scope path
                    # e.g. node.name "invoke" matches scope "StrandsJiraAgent.invoke"
                    node_branches = []
                    for scope, branches in by_scope.items():
                        scope_leaf = scope.split(".")[-1]
                        if scope_leaf == node.name:
                            node_branches.extend(branches)
                    if node_branches:
                        node.metadata["branches"] = node_branches
                        node.metadata["cyclomatic_complexity"] = (
                            sum(
                                sum(1 for a in b["arms"]
                                    if a["kind"] in ("if", "elif", "except", "catch", "case"))
                                for b in node_branches
                            ) + 1
                        )
    except Exception as e:
        logger.warning("Branch extraction failed for %s: %s", file_path, e)

    return result


def parse_directory(root_dir: str, exclude_dirs: Optional[list[str]] = None) -> ParseResult:
    """
    Recursively parse all supported source files in a directory.

    Args:
        root_dir: Root directory of the codebase to parse
        exclude_dirs: Directory names to skip (e.g. node_modules, .git, build)

    Returns:
        Combined ParseResult with all nodes and edges from the codebase
    """
    exclude_dirs = set(exclude_dirs or [
        ".git", "__pycache__", "node_modules", ".venv", "venv",
        "build", "dist", ".terraform", "target",
    ])

    combined = ParseResult()
    root = Path(root_dir)

    for path in root.rglob("*"):
        if path.is_file() and not any(p in exclude_dirs for p in path.parts):
            result = parse_file(str(path))
            combined.nodes.extend(result.nodes)
            combined.edges.extend(result.edges)

    logger.info("Parsed %d nodes and %d edges from %s",
                len(combined.nodes), len(combined.edges), root_dir)
    return combined
