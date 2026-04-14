"""
Graph cache — persists the parsed graph to disk so restarts are instant.

Cache location: ~/.kiro/cache/code-graph/<repo-hash>/graph.json
The repo hash is derived from the absolute repo path, so each repo gets
its own cache slot. The cache is invalidated when any source file is newer
than the cache file.

Scale note: For very large repos the JSON cache can get big. At that point
consider switching to a binary format (msgpack) or just using Neptune as the
persistent store instead.
"""

import hashlib
import json
import logging
import os
import time
from dataclasses import asdict
from pathlib import Path
from typing import Optional

from .parser import GraphNode, GraphEdge, ParseResult

logger = logging.getLogger(__name__)

CACHE_DIR = Path.home() / ".kiro" / "cache" / "code-graph"


def _repo_hash(repo_path: str) -> str:
    """Stable short hash of the repo path — used as the cache directory name."""
    return hashlib.sha1(os.path.abspath(repo_path).encode()).hexdigest()[:12]


def _cache_path(repo_path: str) -> Path:
    return CACHE_DIR / _repo_hash(repo_path) / "graph.json"


def _newest_source_mtime(repo_path: str, exclude_dirs: Optional[set] = None) -> float:
    """Return the most recent modification time across all source files in the repo."""
    exclude_dirs = exclude_dirs or {
        ".git", "__pycache__", "node_modules", ".venv", "venv",
        "build", "dist", ".terraform", "target",
    }
    newest = 0.0
    for path in Path(repo_path).rglob("*"):
        if path.is_file() and not any(p in exclude_dirs for p in path.parts):
            try:
                mtime = path.stat().st_mtime
                if mtime > newest:
                    newest = mtime
            except OSError:
                pass
    return newest


def is_cache_valid(repo_path: str) -> bool:
    """Return True if the cache exists and is newer than all source files."""
    cache = _cache_path(repo_path)
    if not cache.exists():
        return False
    cache_mtime = cache.stat().st_mtime
    source_mtime = _newest_source_mtime(repo_path)
    valid = cache_mtime >= source_mtime
    if valid:
        logger.info("Cache is valid (cache: %.0f, sources: %.0f)", cache_mtime, source_mtime)
    else:
        logger.info("Cache is stale — sources changed since last build")
    return valid


def load_cache(repo_path: str) -> Optional[ParseResult]:
    """Load a ParseResult from the cache. Returns None if cache is missing or invalid."""
    cache = _cache_path(repo_path)
    if not cache.exists():
        return None
    try:
        start = time.time()
        with open(cache) as f:
            data = json.load(f)
        nodes = [GraphNode(**n) for n in data["nodes"]]
        edges = [GraphEdge(**e) for e in data["edges"]]
        elapsed = time.time() - start
        logger.info("Loaded graph from cache in %.2fs (%d nodes, %d edges)",
                    elapsed, len(nodes), len(edges))
        return ParseResult(nodes=nodes, edges=edges)
    except Exception as e:
        logger.warning("Failed to load cache: %s", e)
        return None


def save_cache(repo_path: str, result: ParseResult) -> None:
    """Persist a ParseResult to the cache directory."""
    cache = _cache_path(repo_path)
    try:
        cache.parent.mkdir(parents=True, exist_ok=True)
        start = time.time()
        with open(cache, "w") as f:
            json.dump({
                "nodes": [asdict(n) for n in result.nodes],
                "edges": [asdict(e) for e in result.edges],
            }, f)
        elapsed = time.time() - start
        logger.info("Saved graph cache to %s in %.2fs", cache, elapsed)
    except Exception as e:
        logger.warning("Failed to save cache: %s", e)


def invalidate_cache(repo_path: str) -> None:
    """Delete the cache for a repo (forces full rebuild on next startup)."""
    cache = _cache_path(repo_path)
    if cache.exists():
        cache.unlink()
        logger.info("Cache invalidated: %s", cache)
