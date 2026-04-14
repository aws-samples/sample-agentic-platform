#!/bin/bash
# Code Graph MCP Server — Kiro setup
# Usage: bash setup.sh [path/to/repo]
#
# Installs deps, registers the MCP server in Kiro, and installs the file-watch hook.
# For other clients (Claude Code, etc.) see the Manual setup section in README.md.

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../../../.." && pwd)"
TARGET_REPO="${1:-$REPO_ROOT}"
VENV_DIR="$REPO_ROOT/.venv"
PYTHON="$VENV_DIR/bin/python3.12"
KIRO_MCP="$HOME/.kiro/settings/mcp.json"

# Find the Kiro workspace root by walking up from REPO_ROOT until we find a .kiro dir
# Falls back to REPO_ROOT if none found
_find_kiro_root() {
  local dir="$1"
  while [ "$dir" != "/" ]; do
    if [ -d "$dir/.kiro" ]; then
      echo "$dir"
      return
    fi
    dir="$(dirname "$dir")"
  done
  echo "$1"  # fallback: use the repo root itself
}
KIRO_ROOT="$(_find_kiro_root "$REPO_ROOT")"
KIRO_HOOKS="$KIRO_ROOT/.kiro/hooks"

echo "=== Code Graph MCP Server Setup ==="
echo "Repo root:   $REPO_ROOT"
echo "Target repo: $TARGET_REPO"
echo ""

# 1. Create venv and install deps
echo "[1/3] Installing dependencies..."
if [ ! -d "$VENV_DIR" ]; then
  uv venv "$VENV_DIR"
fi
uv pip install --python "$PYTHON" \
  "mcp>=1.5.0" \
  "networkx>=3.3" \
  "tree-sitter>=0.23.0" \
  "tree-sitter-python>=0.23.0" \
  "tree-sitter-typescript>=0.23.0" \
  "tree-sitter-java>=0.23.0"
echo "    Done."

# 2. Register MCP server in Kiro config
echo "[2/3] Registering MCP server in Kiro..."
mkdir -p "$(dirname "$KIRO_MCP")"
if [ ! -f "$KIRO_MCP" ]; then
  echo '{"mcpServers": {}}' > "$KIRO_MCP"
fi

"$PYTHON" - <<PYEOF
import json

with open("$KIRO_MCP") as f:
    config = json.load(f)

config.setdefault("mcpServers", {})["code-graph"] = {
    "command": "$PYTHON",
    "args": [
        "-m",
        "agentic_platform.mcp_server.code_graph_mcp_server.server",
        "stdio"
    ],
    "env": {
        "REPO_PATH": "$TARGET_REPO",
        "PYTHONPATH": "$REPO_ROOT/src"
    }
}

with open("$KIRO_MCP", "w") as f:
    json.dump(config, f, indent=2)

print("    Wrote code-graph entry to $KIRO_MCP")
PYEOF

# 3. Install Kiro hook
echo "[3/3] Installing file-watch hook..."
mkdir -p "$KIRO_HOOKS"
cp "$SCRIPT_DIR/hooks/kiro-file-update.kiro.hook" "$KIRO_HOOKS/code-graph-file-update.kiro.hook"
echo "    Hook written to $KIRO_HOOKS/code-graph-file-update.kiro.hook"

echo ""
echo "=== Setup complete ==="
echo ""
echo "Next steps:"
echo "  1. Restart Kiro (or reconnect via Command Palette -> 'MCP')"
echo "  2. Ask: 'what calls configure_middleware in this repo?'"
echo ""
echo "To point at a different repo:"
echo "  bash setup.sh /path/to/your/repo"
echo ""
echo "For other clients (Claude Code, etc.) see the Manual setup section in README.md."
