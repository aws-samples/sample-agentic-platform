#!/bin/bash
# ATX Container Entrypoint Script
# This script serves as the container entrypoint and delegates to the orchestrator

set -euo pipefail

# Filter out any arguments that look like script paths
filtered_args=()
for arg in "$@"; do
    # Skip arguments that look like script paths
    if [[ "$arg" != "/usr/local/bin/atx-orchestrator.sh" && "$arg" != "atx-orchestrator.sh" ]]; then
        filtered_args+=("$arg")
    fi
done

# If no arguments provided after filtering, show help
if [[ ${#filtered_args[@]} -eq 0 ]]; then
    exec /usr/local/bin/atx-orchestrator.sh --help
fi

# Pass filtered arguments to the orchestrator
exec /usr/local/bin/atx-orchestrator.sh "${filtered_args[@]}"