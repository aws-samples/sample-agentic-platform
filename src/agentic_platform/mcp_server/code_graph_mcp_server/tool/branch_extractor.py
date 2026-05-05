"""
Polyglot branch extractor using tree-sitter.

Enumerates every decision point in a source file — if/elif/else,
try/catch/finally, switch/case, ternary expressions — for Python,
TypeScript/JavaScript, and Java.  Follows the same per-language adapter
pattern as parser.py so adding a new language is a single function.

Use cases
---------
- Test generation: know every branch before writing a single test
- Code review: surface all conditional logic changed in a diff
- Complexity analysis: rank files/functions by cyclomatic complexity
- Documentation: auto-generate edge-case sections for docstrings
- Security audits: find auth-bypass conditions, bare catch blocks, etc.
"""

from dataclasses import dataclass, field
from pathlib import Path
from typing import Optional
import logging

logger = logging.getLogger(__name__)

# Re-use the language/extension map from the parser so they stay in sync
from agentic_platform.mcp_server.code_graph_mcp_server.tool.parser import EXTENSION_TO_LANGUAGE, _get_parser


# ---------------------------------------------------------------------------
# Shared data model  (language-agnostic)
# ---------------------------------------------------------------------------

@dataclass
class BranchArm:
    """One arm of a branch (if-body, elif, else, catch clause, case, etc.)"""
    kind: str         # "if" | "elif" | "else" | "except" | "catch" | "finally" | "case" | "default"
    condition: str    # Source text of the condition; "" for else/finally/default
    line: int
    end_line: int
    body_summary: str # First ~60 chars of the arm body


@dataclass
class Branch:
    """A single decision point in the source."""
    branch_type: str      # "if" | "try" | "switch" | "ternary" | "match"
    line: int
    end_line: int
    enclosing_scope: str  # e.g. "MyClass.myMethod" or "<module>"
    language: str
    arms: list[BranchArm] = field(default_factory=list)
    condition: str = ""   # Primary condition text (for if/ternary/switch subject)
    description: str = "" # Human-readable one-liner


@dataclass
class BranchReport:
    """Full branch report for a file."""
    file: str
    language: str
    target_scope: Optional[str]
    total_branches: int
    cyclomatic_complexity: int  # decision points + 1
    branches: list[Branch] = field(default_factory=list)
    summary: str = ""


# ---------------------------------------------------------------------------
# Shared tree-sitter helpers
# ---------------------------------------------------------------------------

def _text(node, src: bytes) -> str:
    """Extract raw source text for a tree-sitter node."""
    return src[node.start_byte:node.end_byte].decode("utf-8", errors="replace")


def _short(text: str, max_len: int = 80) -> str:
    text = text.replace("\n", " ").strip()
    return text if len(text) <= max_len else text[:max_len - 1] + "…"


def _first_child_text(node, src: bytes, max_len: int = 60) -> str:
    """Summarise the first named child of a block node."""
    for child in node.children:
        if child.is_named:
            return _short(_text(child, src), max_len)
    return "(empty)"


def _node_end_line(node) -> int:
    return node.end_point[0] + 1


# ---------------------------------------------------------------------------
# Python adapter  (tree-sitter)
# ---------------------------------------------------------------------------

def _extract_python(src: bytes, scope: Optional[str]) -> list[Branch]:
    parser = _get_parser("python")
    if not parser:
        return []

    tree = parser.parse(src)
    branches: list[Branch] = []
    scope_stack: list[str] = []

    def current_scope() -> str:
        return ".".join(scope_stack) if scope_stack else "<module>"

    def in_target() -> bool:
        if scope is None:
            return True
        s = current_scope()
        return s == scope or s.startswith(scope + ".")

    def walk(node):
        t = node.type

        # --- scope tracking ---
        if t in ("function_definition", "async_function_definition"):
            name_node = node.child_by_field_name("name")
            name = _text(name_node, src) if name_node else "<anon>"
            scope_stack.append(name)
            for child in node.children:
                walk(child)
            scope_stack.pop()
            return

        if t == "class_definition":
            name_node = node.child_by_field_name("name")
            name = _text(name_node, src) if name_node else "<anon>"
            scope_stack.append(name)
            for child in node.children:
                walk(child)
            scope_stack.pop()
            return

        # --- if / elif / else ---
        if t == "if_statement" and in_target():
            arms: list[BranchArm] = []
            cond_node = node.child_by_field_name("condition")
            cond = _short(_text(cond_node, src)) if cond_node else ""
            body_node = node.child_by_field_name("body")
            arms.append(BranchArm(
                kind="if", condition=cond,
                line=node.start_point[0] + 1,
                end_line=_node_end_line(node),
                body_summary=_first_child_text(body_node, src) if body_node else "",
            ))
            for child in node.children:
                if child.type == "elif_clause":
                    elif_cond = child.child_by_field_name("condition")
                    elif_body = child.child_by_field_name("body")
                    arms.append(BranchArm(
                        kind="elif",
                        condition=_short(_text(elif_cond, src)) if elif_cond else "",
                        line=child.start_point[0] + 1,
                        end_line=_node_end_line(child),
                        body_summary=_first_child_text(elif_body, src) if elif_body else "",
                    ))
                elif child.type == "else_clause":
                    else_body = child.child_by_field_name("body")
                    arms.append(BranchArm(
                        kind="else", condition="",
                        line=child.start_point[0] + 1,
                        end_line=_node_end_line(child),
                        body_summary=_first_child_text(else_body, src) if else_body else "",
                    ))
            desc_parts = []
            for a in arms:
                if a.kind in ("if", "elif"):
                    desc_parts.append(f"{a.kind} `{a.condition}` → {a.body_summary}")
                else:
                    desc_parts.append(f"else → {a.body_summary}")
            branches.append(Branch(
                branch_type="if", line=node.start_point[0] + 1,
                end_line=_node_end_line(node), enclosing_scope=current_scope(),
                language="python", arms=arms, condition=cond,
                description="; ".join(desc_parts),
            ))

        # --- try / except / finally ---
        elif t == "try_statement" and in_target():
            arms = []
            body_node = node.child_by_field_name("body")
            arms.append(BranchArm(
                kind="try", condition="",
                line=node.start_point[0] + 1, end_line=node.start_point[0] + 1,
                body_summary=_first_child_text(body_node, src) if body_node else "",
            ))
            bare_except = False
            for child in node.children:
                if child.type == "except_clause":
                    # Children: "except" [type_node ["as" name]] ":" block
                    exc_parts = [c for c in child.children
                                 if c.is_named and c.type not in ("block",)]
                    if exc_parts:
                        exc_text = _short(_text(exc_parts[0], src))
                    else:
                        exc_text = "*"
                        bare_except = True
                    exc_body = child.child_by_field_name("body")
                    arms.append(BranchArm(
                        kind="except", condition=exc_text,
                        line=child.start_point[0] + 1, end_line=_node_end_line(child),
                        body_summary=_first_child_text(exc_body, src) if exc_body else "",
                    ))
                elif child.type == "else_clause":
                    else_body = child.child_by_field_name("body")
                    arms.append(BranchArm(
                        kind="else", condition="(no exception)",
                        line=child.start_point[0] + 1, end_line=_node_end_line(child),
                        body_summary=_first_child_text(else_body, src) if else_body else "",
                    ))
                elif child.type == "finally_clause":
                    fin_body = child.child_by_field_name("body")
                    arms.append(BranchArm(
                        kind="finally", condition="",
                        line=child.start_point[0] + 1, end_line=_node_end_line(child),
                        body_summary=_first_child_text(fin_body, src) if fin_body else "",
                    ))
            exc_count = sum(1 for a in arms if a.kind == "except")
            has_finally = any(a.kind == "finally" for a in arms)
            desc = f"try/except with {exc_count} handler(s)"
            if bare_except:
                desc += " [⚠ bare except]"
            if has_finally:
                desc += " + finally"
            branches.append(Branch(
                branch_type="try", line=node.start_point[0] + 1,
                end_line=_node_end_line(node), enclosing_scope=current_scope(),
                language="python", arms=arms, description=desc,
            ))

        # --- match / case (Python 3.10+) ---
        elif t == "match_statement" and in_target():
            subject_node = node.child_by_field_name("subject")
            subject = _short(_text(subject_node, src)) if subject_node else ""
            arms = []
            for child in node.children:
                if child.type == "case_clause":
                    pattern = child.child_by_field_name("pattern")
                    guard = child.child_by_field_name("guard")
                    body = child.child_by_field_name("body")
                    cond_text = _short(_text(pattern, src)) if pattern else ""
                    if guard:
                        cond_text += f" if {_short(_text(guard, src))}"
                    arms.append(BranchArm(
                        kind="case", condition=cond_text,
                        line=child.start_point[0] + 1, end_line=_node_end_line(child),
                        body_summary=_first_child_text(body, src) if body else "",
                    ))
            branches.append(Branch(
                branch_type="match", line=node.start_point[0] + 1,
                end_line=_node_end_line(node), enclosing_scope=current_scope(),
                language="python", arms=arms, condition=subject,
                description=f"match `{subject}` with {len(arms)} case(s)",
            ))

        # --- ternary (conditional_expression) ---
        elif t == "conditional_expression" and in_target():
            # tree-sitter python: body "if" test "else" alternative
            children = [c for c in node.children if c.is_named]
            # children order: value_if_true, condition, value_if_false
            if len(children) >= 3:
                true_val = _short(_text(children[0], src), 40)
                cond = _short(_text(children[1], src))
                false_val = _short(_text(children[2], src), 40)
            else:
                cond = _short(_text(node, src))
                true_val = false_val = ""
            branches.append(Branch(
                branch_type="ternary", line=node.start_point[0] + 1,
                end_line=_node_end_line(node), enclosing_scope=current_scope(),
                language="python",
                arms=[
                    BranchArm(kind="if", condition=cond, line=node.start_point[0] + 1,
                              end_line=node.start_point[0] + 1, body_summary=true_val),
                    BranchArm(kind="else", condition="", line=node.start_point[0] + 1,
                              end_line=node.start_point[0] + 1, body_summary=false_val),
                ],
                condition=cond,
                description=f"`{true_val}` if `{cond}` else `{false_val}`",
            ))

        for child in node.children:
            walk(child)

    walk(tree.root_node)
    return branches


# ---------------------------------------------------------------------------
# TypeScript / JavaScript adapter  (tree-sitter)
# ---------------------------------------------------------------------------

def _extract_typescript(src: bytes, scope: Optional[str]) -> list[Branch]:
    parser = _get_parser("typescript")
    if not parser:
        return []

    tree = parser.parse(src)
    branches: list[Branch] = []
    scope_stack: list[str] = []

    def current_scope() -> str:
        return ".".join(scope_stack) if scope_stack else "<module>"

    def in_target() -> bool:
        if scope is None:
            return True
        s = current_scope()
        return s == scope or s.startswith(scope + ".")

    def walk(node):
        t = node.type

        # --- scope tracking ---
        if t in ("function_declaration", "method_definition",
                 "arrow_function", "function_expression"):
            name_node = node.child_by_field_name("name")
            name = _text(name_node, src) if name_node else "<anon>"
            scope_stack.append(name)
            for child in node.children:
                walk(child)
            scope_stack.pop()
            return

        if t in ("class_declaration", "class_expression"):
            name_node = node.child_by_field_name("name")
            name = _text(name_node, src) if name_node else "<anon>"
            scope_stack.append(name)
            for child in node.children:
                walk(child)
            scope_stack.pop()
            return

        # --- if / else if / else ---
        if t == "if_statement" and in_target():
            arms: list[BranchArm] = []

            def collect_if(n):
                cond_node = n.child_by_field_name("condition")
                cond = _short(_text(cond_node, src)) if cond_node else ""
                # strip outer parens from (x > 0)
                if cond.startswith("(") and cond.endswith(")"):
                    cond = cond[1:-1].strip()
                cons_node = n.child_by_field_name("consequence")
                arms.append(BranchArm(
                    kind="if" if not arms else "elif",
                    condition=cond,
                    line=n.start_point[0] + 1,
                    end_line=_node_end_line(n),
                    body_summary=_first_child_text(cons_node, src) if cons_node else "",
                ))
                alt_node = n.child_by_field_name("alternative")
                if alt_node:
                    # else_clause wraps either another if_statement or a block
                    inner = next((c for c in alt_node.children if c.is_named), None)
                    if inner and inner.type == "if_statement":
                        collect_if(inner)
                    else:
                        arms.append(BranchArm(
                            kind="else", condition="",
                            line=alt_node.start_point[0] + 1,
                            end_line=_node_end_line(alt_node),
                            body_summary=_first_child_text(alt_node, src),
                        ))

            collect_if(node)
            cond = arms[0].condition if arms else ""
            desc_parts = [
                (f"{a.kind} `{a.condition}` → {a.body_summary}"
                 if a.kind != "else" else f"else → {a.body_summary}")
                for a in arms
            ]
            branches.append(Branch(
                branch_type="if", line=node.start_point[0] + 1,
                end_line=_node_end_line(node), enclosing_scope=current_scope(),
                language="typescript", arms=arms, condition=cond,
                description="; ".join(desc_parts),
            ))

        # --- try / catch / finally ---
        elif t == "try_statement" and in_target():
            arms = []
            body_node = node.child_by_field_name("body")
            arms.append(BranchArm(
                kind="try", condition="",
                line=node.start_point[0] + 1, end_line=node.start_point[0] + 1,
                body_summary=_first_child_text(body_node, src) if body_node else "",
            ))
            for child in node.children:
                if child.type == "catch_clause":
                    # parameter is the catch binding: catch (e)
                    param = child.child_by_field_name("parameter")
                    exc_text = _short(_text(param, src)) if param else "*"
                    catch_body = child.child_by_field_name("body")
                    arms.append(BranchArm(
                        kind="catch", condition=exc_text,
                        line=child.start_point[0] + 1, end_line=_node_end_line(child),
                        body_summary=_first_child_text(catch_body, src) if catch_body else "",
                    ))
                elif child.type == "finally_clause":
                    fin_body = next((c for c in child.children
                                     if c.type == "statement_block"), None)
                    arms.append(BranchArm(
                        kind="finally", condition="",
                        line=child.start_point[0] + 1, end_line=_node_end_line(child),
                        body_summary=_first_child_text(fin_body, src) if fin_body else "",
                    ))
            catch_count = sum(1 for a in arms if a.kind == "catch")
            has_finally = any(a.kind == "finally" for a in arms)
            desc = f"try/catch with {catch_count} handler(s)"
            if has_finally:
                desc += " + finally"
            branches.append(Branch(
                branch_type="try", line=node.start_point[0] + 1,
                end_line=_node_end_line(node), enclosing_scope=current_scope(),
                language="typescript", arms=arms, description=desc,
            ))

        # --- switch / case / default ---
        elif t == "switch_statement" and in_target():
            val_node = node.child_by_field_name("value")
            subject = _short(_text(val_node, src)) if val_node else ""
            if subject.startswith("(") and subject.endswith(")"):
                subject = subject[1:-1].strip()
            arms = []
            body_node = node.child_by_field_name("body")
            if body_node:
                for child in body_node.children:
                    if child.type == "switch_case":
                        val = next((c for c in child.children
                                    if c.is_named and c.type not in
                                    ("statement_block", "break_statement",
                                     "return_statement", "expression_statement")), None)
                        cond_text = _short(_text(val, src)) if val else ""
                        stmts = [c for c in child.children
                                 if c.is_named and c.type not in
                                 ("break_statement",) and c is not val]
                        arms.append(BranchArm(
                            kind="case", condition=cond_text,
                            line=child.start_point[0] + 1, end_line=_node_end_line(child),
                            body_summary=_short(_text(stmts[0], src), 60) if stmts else "",
                        ))
                    elif child.type == "switch_default":
                        stmts = [c for c in child.children
                                 if c.is_named and c.type not in ("break_statement",)]
                        arms.append(BranchArm(
                            kind="default", condition="",
                            line=child.start_point[0] + 1, end_line=_node_end_line(child),
                            body_summary=_short(_text(stmts[0], src), 60) if stmts else "",
                        ))
            branches.append(Branch(
                branch_type="switch", line=node.start_point[0] + 1,
                end_line=_node_end_line(node), enclosing_scope=current_scope(),
                language="typescript", arms=arms, condition=subject,
                description=f"switch `{subject}` with {len(arms)} case(s)",
            ))

        # --- ternary expression ---
        elif t == "ternary_expression" and in_target():
            cond_node = node.child_by_field_name("condition")
            cons_node = node.child_by_field_name("consequence")
            alt_node  = node.child_by_field_name("alternative")
            cond      = _short(_text(cond_node, src)) if cond_node else ""
            true_val  = _short(_text(cons_node, src), 40) if cons_node else ""
            false_val = _short(_text(alt_node,  src), 40) if alt_node  else ""
            branches.append(Branch(
                branch_type="ternary", line=node.start_point[0] + 1,
                end_line=_node_end_line(node), enclosing_scope=current_scope(),
                language="typescript",
                arms=[
                    BranchArm(kind="if", condition=cond, line=node.start_point[0] + 1,
                              end_line=node.start_point[0] + 1, body_summary=true_val),
                    BranchArm(kind="else", condition="", line=node.start_point[0] + 1,
                              end_line=node.start_point[0] + 1, body_summary=false_val),
                ],
                condition=cond,
                description=f"`{true_val}` if `{cond}` else `{false_val}`",
            ))

        for child in node.children:
            walk(child)

    walk(tree.root_node)
    return branches


# ---------------------------------------------------------------------------
# Java adapter  (tree-sitter)
# ---------------------------------------------------------------------------

def _extract_java(src: bytes, scope: Optional[str]) -> list[Branch]:
    parser = _get_parser("java")
    if not parser:
        return []

    tree = parser.parse(src)
    branches: list[Branch] = []
    scope_stack: list[str] = []

    def current_scope() -> str:
        return ".".join(scope_stack) if scope_stack else "<module>"

    def in_target() -> bool:
        if scope is None:
            return True
        s = current_scope()
        return s == scope or s.startswith(scope + ".")

    def walk(node):
        t = node.type

        # --- scope tracking ---
        if t == "class_declaration":
            name_node = node.child_by_field_name("name")
            name = _text(name_node, src) if name_node else "<anon>"
            scope_stack.append(name)
            for child in node.children:
                walk(child)
            scope_stack.pop()
            return

        if t == "method_declaration":
            name_node = node.child_by_field_name("name")
            name = _text(name_node, src) if name_node else "<anon>"
            scope_stack.append(name)
            for child in node.children:
                walk(child)
            scope_stack.pop()
            return

        # --- if / else if / else ---
        if t == "if_statement" and in_target():
            arms: list[BranchArm] = []

            def collect_if(n):
                cond_node = n.child_by_field_name("condition")
                cond = _short(_text(cond_node, src)) if cond_node else ""
                if cond.startswith("(") and cond.endswith(")"):
                    cond = cond[1:-1].strip()
                cons_node = n.child_by_field_name("consequence")
                arms.append(BranchArm(
                    kind="if" if not arms else "elif",
                    condition=cond,
                    line=n.start_point[0] + 1,
                    end_line=_node_end_line(n),
                    body_summary=_first_child_text(cons_node, src) if cons_node else "",
                ))
                alt_node = n.child_by_field_name("alternative")
                if alt_node:
                    inner = next((c for c in alt_node.children if c.is_named), None)
                    if inner and inner.type == "if_statement":
                        collect_if(inner)
                    else:
                        arms.append(BranchArm(
                            kind="else", condition="",
                            line=alt_node.start_point[0] + 1,
                            end_line=_node_end_line(alt_node),
                            body_summary=_first_child_text(alt_node, src),
                        ))

            collect_if(node)
            cond = arms[0].condition if arms else ""
            desc_parts = [
                (f"{a.kind} `{a.condition}` → {a.body_summary}"
                 if a.kind != "else" else f"else → {a.body_summary}")
                for a in arms
            ]
            branches.append(Branch(
                branch_type="if", line=node.start_point[0] + 1,
                end_line=_node_end_line(node), enclosing_scope=current_scope(),
                language="java", arms=arms, condition=cond,
                description="; ".join(desc_parts),
            ))

        # --- try / catch / finally ---
        elif t == "try_statement" and in_target():
            arms = []
            body_node = node.child_by_field_name("body")
            arms.append(BranchArm(
                kind="try", condition="",
                line=node.start_point[0] + 1, end_line=node.start_point[0] + 1,
                body_summary=_first_child_text(body_node, src) if body_node else "",
            ))
            for child in node.children:
                if child.type == "catch_clause":
                    param = child.child_by_field_name("catch_formal_parameter")
                    if param is None:
                        # fallback: grab first named child that isn't the body
                        param = next((c for c in child.children
                                      if c.is_named and c.type != "block"), None)
                    exc_text = _short(_text(param, src)) if param else "*"
                    catch_body = child.child_by_field_name("body")
                    arms.append(BranchArm(
                        kind="catch", condition=exc_text,
                        line=child.start_point[0] + 1, end_line=_node_end_line(child),
                        body_summary=_first_child_text(catch_body, src) if catch_body else "",
                    ))
                elif child.type == "finally_clause":
                    fin_body = next((c for c in child.children if c.type == "block"), None)
                    arms.append(BranchArm(
                        kind="finally", condition="",
                        line=child.start_point[0] + 1, end_line=_node_end_line(child),
                        body_summary=_first_child_text(fin_body, src) if fin_body else "",
                    ))
            catch_count = sum(1 for a in arms if a.kind == "catch")
            has_finally = any(a.kind == "finally" for a in arms)
            desc = f"try/catch with {catch_count} handler(s)"
            if has_finally:
                desc += " + finally"
            branches.append(Branch(
                branch_type="try", line=node.start_point[0] + 1,
                end_line=_node_end_line(node), enclosing_scope=current_scope(),
                language="java", arms=arms, description=desc,
            ))

        # --- switch / case / default ---
        elif t in ("switch_expression", "switch_statement") and in_target():
            cond_node = node.child_by_field_name("condition")
            subject = _short(_text(cond_node, src)) if cond_node else ""
            if subject.startswith("(") and subject.endswith(")"):
                subject = subject[1:-1].strip()
            arms = []
            for child in node.children:
                if child.type == "switch_block":
                    for group in child.children:
                        if group.type == "switch_block_statement_group":
                            labels = [c for c in group.children if c.type == "switch_label"]
                            stmts  = [c for c in group.children
                                      if c.is_named and c.type != "switch_label"]
                            for label in labels:
                                # switch_label: "case" value ":" or "default" ":"
                                val_nodes = [c for c in label.children
                                             if c.is_named]
                                if val_nodes:
                                    cond_text = _short(_text(val_nodes[0], src))
                                    kind = "case"
                                else:
                                    cond_text = ""
                                    kind = "default"
                                arms.append(BranchArm(
                                    kind=kind, condition=cond_text,
                                    line=group.start_point[0] + 1,
                                    end_line=_node_end_line(group),
                                    body_summary=_short(_text(stmts[0], src), 60) if stmts else "",
                                ))
            branches.append(Branch(
                branch_type="switch", line=node.start_point[0] + 1,
                end_line=_node_end_line(node), enclosing_scope=current_scope(),
                language="java", arms=arms, condition=subject,
                description=f"switch `{subject}` with {len(arms)} case(s)",
            ))

        # --- ternary expression ---
        elif t == "ternary_expression" and in_target():
            cond_node = node.child_by_field_name("condition")
            cons_node = node.child_by_field_name("consequence")
            alt_node  = node.child_by_field_name("alternative")
            cond      = _short(_text(cond_node, src)) if cond_node else ""
            true_val  = _short(_text(cons_node, src), 40) if cons_node else ""
            false_val = _short(_text(alt_node,  src), 40) if alt_node  else ""
            branches.append(Branch(
                branch_type="ternary", line=node.start_point[0] + 1,
                end_line=_node_end_line(node), enclosing_scope=current_scope(),
                language="java",
                arms=[
                    BranchArm(kind="if", condition=cond, line=node.start_point[0] + 1,
                              end_line=node.start_point[0] + 1, body_summary=true_val),
                    BranchArm(kind="else", condition="", line=node.start_point[0] + 1,
                              end_line=node.start_point[0] + 1, body_summary=false_val),
                ],
                condition=cond,
                description=f"`{true_val}` if `{cond}` else `{false_val}`",
            ))

        for child in node.children:
            walk(child)

    walk(tree.root_node)
    return branches


# ---------------------------------------------------------------------------
# Adapter registry  (mirrors parser.py _ADAPTERS pattern)
# ---------------------------------------------------------------------------

_BRANCH_ADAPTERS = {
    "python":     _extract_python,
    "typescript": _extract_typescript,
    "javascript": _extract_typescript,   # reuse TS adapter
    "java":       _extract_java,
    # terraform/HCL has no meaningful branch constructs to extract
}


# ---------------------------------------------------------------------------
# Public API
# ---------------------------------------------------------------------------

def extract_branches(
    file_path: str,
    scope: Optional[str] = None,
) -> BranchReport:
    """
    Extract all branch points from a source file.

    Supports Python, TypeScript, JavaScript, and Java.
    Uses tree-sitter for all languages — same parser as the code graph.

    Args:
        file_path: Path to the source file.
        scope: Optional function or class name to restrict analysis to.
               Supports dotted names like "MyClass.myMethod".
               If None, the entire file is analysed.

    Returns:
        BranchReport with all branches, cyclomatic complexity, and summary.
    """
    path = Path(file_path)
    if not path.exists():
        return BranchReport(
            file=file_path, language="unknown", target_scope=scope,
            total_branches=0, cyclomatic_complexity=1,
            summary=f"File not found: {file_path}",
        )

    language = EXTENSION_TO_LANGUAGE.get(path.suffix.lower())
    if not language:
        return BranchReport(
            file=file_path, language="unknown", target_scope=scope,
            total_branches=0, cyclomatic_complexity=1,
            summary=f"Unsupported file type: {path.suffix}",
        )

    adapter = _BRANCH_ADAPTERS.get(language)
    if not adapter:
        return BranchReport(
            file=file_path, language=language, target_scope=scope,
            total_branches=0, cyclomatic_complexity=1,
            summary=f"Branch extraction not supported for {language}",
        )

    try:
        src = path.read_bytes()
    except OSError as e:
        return BranchReport(
            file=file_path, language=language, target_scope=scope,
            total_branches=0, cyclomatic_complexity=1,
            summary=f"Could not read file: {e}",
        )

    try:
        branches = adapter(src, scope)
    except Exception as e:
        logger.warning("Branch extraction failed for %s: %s", file_path, e)
        return BranchReport(
            file=file_path, language=language, target_scope=scope,
            total_branches=0, cyclomatic_complexity=1,
            summary=f"Extraction error: {e}",
        )

    # Cyclomatic complexity: count decision arms (if/elif/except/catch/case)
    # else/finally/try arms don't add a branch point
    decision_arms = {"if", "elif", "except", "catch", "case"}
    decision_points = sum(
        sum(1 for a in b.arms if a.kind in decision_arms)
        for b in branches
    )
    complexity = decision_points + 1

    by_type: dict[str, int] = {}
    for b in branches:
        by_type[b.branch_type] = by_type.get(b.branch_type, 0) + 1

    type_summary = ", ".join(
        f"{count} {btype}" for btype, count in sorted(by_type.items())
    )
    scope_label = f"in `{scope}`" if scope else "across file"
    summary = (
        f"{len(branches)} branch point(s) {scope_label} "
        f"(cyclomatic complexity: {complexity})"
        + (f" — {type_summary}" if type_summary else "")
    )

    return BranchReport(
        file=file_path,
        language=language,
        target_scope=scope,
        total_branches=len(branches),
        cyclomatic_complexity=complexity,
        branches=branches,
        summary=summary,
    )


def branch_report_to_dict(report: BranchReport) -> dict:
    """Serialise a BranchReport to a JSON-safe dict for MCP responses."""
    return {
        "file": report.file,
        "language": report.language,
        "target_scope": report.target_scope,
        "total_branches": report.total_branches,
        "cyclomatic_complexity": report.cyclomatic_complexity,
        "summary": report.summary,
        "branches": [
            {
                "branch_type": b.branch_type,
                "line": b.line,
                "end_line": b.end_line,
                "enclosing_scope": b.enclosing_scope,
                "condition": b.condition,
                "description": b.description,
                "arms": [
                    {
                        "kind": a.kind,
                        "condition": a.condition,
                        "line": a.line,
                        "end_line": a.end_line,
                        "body_summary": a.body_summary,
                    }
                    for a in b.arms
                ],
            }
            for b in report.branches
        ],
    }
