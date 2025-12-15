#!/bin/bash
# Minimal test orchestrator to debug argument parsing

echo "[TEST] Script name: $0"
echo "[TEST] Number of arguments: $#"
echo "[TEST] All arguments: $*"

for i in $(seq 1 $#); do
    echo "[TEST] Arg $i: ${!i}"
done

if [[ $# -eq 1 && "$1" == "--smoke-test" ]]; then
    echo "[TEST] SUCCESS: Received --smoke-test argument correctly"
    exit 0
else
    echo "[TEST] ERROR: Expected --smoke-test, got: $1"
    exit 1
fi