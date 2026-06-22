#!/bin/bash
# Example: CI/CD Integration with Exit Code Handling
# This script demonstrates how to use the ATX orchestrator in a CI/CD pipeline
# with proper exit code handling

set -euo pipefail

# Configuration
CSV_FILE="${CSV_FILE:-repos.csv}"
OUTPUT_DIR="${OUTPUT_DIR:-./ci_results}"
MODE="${MODE:-parallel}"
MAX_JOBS="${MAX_JOBS:-4}"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo "=========================================="
echo "CI/CD Pipeline: ATX Transformation Tests"
echo "=========================================="
echo ""
echo "Configuration:"
echo "  CSV File: $CSV_FILE"
echo "  Output Directory: $OUTPUT_DIR"
echo "  Execution Mode: $MODE"
echo "  Max Parallel Jobs: $MAX_JOBS"
echo ""

# Step 1: Validate prerequisites
echo -e "${BLUE}Step 1: Validating prerequisites...${NC}"

if ! command -v atx &> /dev/null; then
    echo -e "${RED}ERROR: ATX CLI not found${NC}"
    echo "Please install ATX CLI before running this pipeline"
    exit 2
fi

if ! command -v aws &> /dev/null; then
    echo -e "${RED}ERROR: AWS CLI not found${NC}"
    echo "Please install AWS CLI before running this pipeline"
    exit 2
fi

if [[ ! -f "$CSV_FILE" ]]; then
    echo -e "${RED}ERROR: CSV file not found: $CSV_FILE${NC}"
    exit 2
fi

echo -e "${GREEN}✓ Prerequisites validated${NC}"
echo ""

# Step 2: Run smoke test (optional but recommended)
echo -e "${BLUE}Step 2: Running smoke test...${NC}"

if ./scripts/atx-orchestrator.sh --smoke-test; then
    echo -e "${GREEN}✓ Smoke test passed${NC}"
else
    smoke_exit_code=$?
    echo -e "${RED}✗ Smoke test failed (exit code: $smoke_exit_code)${NC}"
    echo "Container is not properly configured. Please review smoke test logs."
    exit $smoke_exit_code
fi
echo ""

# Step 3: Execute transformations
echo -e "${BLUE}Step 3: Executing ATX transformations...${NC}"

# Use quiet mode in CI/CD to reduce log noise
# Full logs are still written to files
if ./scripts/atx-orchestrator.sh \
    --csv-file "$CSV_FILE" \
    --output-dir "$OUTPUT_DIR" \
    --mode "$MODE" \
    --max-jobs "$MAX_JOBS" \
    --quiet; then
    
    echo -e "${GREEN}✓ All transformations completed successfully${NC}"
    transformation_exit_code=0
else
    transformation_exit_code=$?
    echo -e "${RED}✗ One or more transformations failed (exit code: $transformation_exit_code)${NC}"
fi
echo ""

# Step 4: Parse results and generate report
echo -e "${BLUE}Step 4: Analyzing results...${NC}"

if [[ -f "$OUTPUT_DIR/results.json" ]]; then
    # Extract statistics from JSON
    total=$(jq -r '.summary.total' "$OUTPUT_DIR/results.json" 2>/dev/null || echo "0")
    successful=$(jq -r '.summary.successful' "$OUTPUT_DIR/results.json" 2>/dev/null || echo "0")
    failed=$(jq -r '.summary.failed' "$OUTPUT_DIR/results.json" 2>/dev/null || echo "0")
    success_rate=$(jq -r '.summary.success_rate' "$OUTPUT_DIR/results.json" 2>/dev/null || echo "0")
    
    echo "Results Summary:"
    echo "  Total folders: $total"
    echo "  Successful: $successful"
    echo "  Failed: $failed"
    echo "  Success rate: ${success_rate}%"
    echo ""
    
    # Display failed folders if any
    if [[ $failed -gt 0 ]]; then
        echo -e "${YELLOW}Failed Folders:${NC}"
        jq -r '.tests[] | select(.status == "FAILED") | "  - \(.name): \(.message)"' "$OUTPUT_DIR/results.json" 2>/dev/null || echo "  (Unable to parse failed folders)"
        echo ""
    fi
else
    echo -e "${YELLOW}Warning: results.json not found${NC}"
fi

# Step 5: Upload artifacts (example)
echo -e "${BLUE}Step 5: Uploading artifacts...${NC}"

# Example: Upload to S3 (uncomment if needed)
# if [[ -n "${CI_ARTIFACTS_BUCKET:-}" ]]; then
#     aws s3 sync "$OUTPUT_DIR" "s3://$CI_ARTIFACTS_BUCKET/builds/$CI_BUILD_ID/" --quiet
#     echo -e "${GREEN}✓ Artifacts uploaded to S3${NC}"
# else
#     echo "Skipping artifact upload (CI_ARTIFACTS_BUCKET not set)"
# fi

echo "Artifacts available at: $OUTPUT_DIR"
echo ""

# Step 6: Final status
echo "=========================================="
if [[ $transformation_exit_code -eq 0 ]]; then
    echo -e "${GREEN}CI/CD Pipeline: SUCCESS${NC}"
    echo "All transformations completed successfully"
else
    echo -e "${RED}CI/CD Pipeline: FAILURE${NC}"
    echo "One or more transformations failed"
    echo ""
    echo "Troubleshooting:"
    echo "  1. Review summary log: $OUTPUT_DIR/summary.log"
    echo "  2. Check individual logs: $OUTPUT_DIR/*_execution.log"
    echo "  3. Inspect results JSON: $OUTPUT_DIR/results.json"
fi
echo "=========================================="

# Exit with the transformation exit code
exit $transformation_exit_code
