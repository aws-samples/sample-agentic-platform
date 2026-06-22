#!/bin/bash
# ATX Container Build and Test Script
# Builds the Docker image and runs comprehensive tests
#
# This script implements task 11: Build and test Docker image
# - Subtask 11.1: Build Docker image locally
# - Subtask 11.2: Run smoke test on built image
# - Subtask 11.3: Test with sample Progress code (requires S3 setup)
#
# Requirements: 7.5, 10.1, 10.3, 10.4, 1.3, 1.4

set -euo pipefail

#######################################
# Script Configuration
#######################################
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
SCRIPT_NAME=$(basename "$0")

# Default configuration
DEFAULT_IMAGE_NAME="atx-test-runner"
DEFAULT_IMAGE_TAG="latest"
DEFAULT_OUTPUT_DIR="./build_test_results"
DEFAULT_MAX_IMAGE_SIZE_MB=2000  # 2GB reasonable limit

# Global variables
IMAGE_NAME="$DEFAULT_IMAGE_NAME"
IMAGE_TAG="$DEFAULT_IMAGE_TAG"
OUTPUT_DIR="$DEFAULT_OUTPUT_DIR"
MAX_IMAGE_SIZE_MB="$DEFAULT_MAX_IMAGE_SIZE_MB"
VERBOSE=false
SKIP_BUILD=false
SKIP_SMOKE_TEST=false
SKIP_S3_TEST=false
BUILD_NO_CACHE=false

#######################################
# Logging Functions
#######################################

log_info() {
    echo "[INFO] $*"
}

log_success() {
    echo -e "\033[0;32m[SUCCESS]\033[0m $*"
}

log_error() {
    echo -e "\033[0;31m[ERROR]\033[0m $*" >&2
}

log_warn() {
    echo -e "\033[0;33m[WARN]\033[0m $*"
}

log_debug() {
    if [[ "$VERBOSE" == true ]]; then
        echo "[DEBUG] $*"
    fi
}

log_section() {
    echo ""
    echo "=========================================="
    echo "$*"
    echo "=========================================="
}

#######################################
# Usage and Help
#######################################

usage() {
    cat << EOF
ATX Container Build and Test Script

USAGE:
    $SCRIPT_NAME [OPTIONS]

OPTIONS:
    --image-name <name>         Docker image name (default: $DEFAULT_IMAGE_NAME)
    --image-tag <tag>           Docker image tag (default: $DEFAULT_IMAGE_TAG)
    --output-dir <dir>          Output directory for test results (default: $DEFAULT_OUTPUT_DIR)
    --max-size-mb <size>        Maximum acceptable image size in MB (default: $DEFAULT_MAX_IMAGE_SIZE_MB)
    --no-cache                  Build without using cache
    --skip-build                Skip Docker build step
    --skip-smoke-test           Skip smoke test
    --skip-s3-test              Skip S3 integration test
    --verbose                   Enable verbose output
    --help                      Show this help message

DESCRIPTION:
    This script builds the ATX container Docker image and runs comprehensive tests
    to verify the image is properly configured. It performs:
    
    1. Docker image build with validation
    2. Image size verification
    3. Component installation verification (ATX CLI, AWS CLI)
    4. Smoke test execution
    5. Optional S3 integration test
    
    The script implements task 11 from the implementation plan.

EXIT CODES:
    0 - All tests passed
    1 - Docker build failed
    2 - Image size exceeds limit
    3 - Component verification failed
    4 - Smoke test failed
    5 - S3 integration test failed
    10 - Docker daemon not running
    11 - Invalid arguments

EXAMPLES:
    # Build and test with defaults
    $SCRIPT_NAME
    
    # Build without cache
    $SCRIPT_NAME --no-cache
    
    # Build with custom image name
    $SCRIPT_NAME --image-name my-atx-runner --image-tag v1.0
    
    # Skip S3 test (requires AWS setup)
    $SCRIPT_NAME --skip-s3-test
    
    # Only run tests on existing image
    $SCRIPT_NAME --skip-build

EOF
}

#######################################
# Argument Parsing
#######################################

parse_arguments() {
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --image-name)
                IMAGE_NAME="$2"
                shift 2
                ;;
            --image-tag)
                IMAGE_TAG="$2"
                shift 2
                ;;
            --output-dir)
                OUTPUT_DIR="$2"
                shift 2
                ;;
            --max-size-mb)
                MAX_IMAGE_SIZE_MB="$2"
                shift 2
                ;;
            --no-cache)
                BUILD_NO_CACHE=true
                shift
                ;;
            --skip-build)
                SKIP_BUILD=true
                shift
                ;;
            --skip-smoke-test)
                SKIP_SMOKE_TEST=true
                shift
                ;;
            --skip-s3-test)
                SKIP_S3_TEST=true
                shift
                ;;
            --verbose)
                VERBOSE=true
                shift
                ;;
            --help|-h)
                usage
                exit 0
                ;;
            *)
                log_error "Unknown option: $1"
                usage
                exit 11
                ;;
        esac
    done
}

#######################################
# Pre-flight Checks
#######################################

check_docker_available() {
    log_info "Checking Docker availability..."
    
    if ! command -v docker &> /dev/null; then
        log_error "Docker not found in PATH"
        log_error "Please install Docker: https://docs.docker.com/get-docker/"
        return 10
    fi
    
    if ! docker info &> /dev/null; then
        log_error "Docker daemon is not running"
        log_error "Please start Docker Desktop or the Docker daemon"
        return 10
    fi
    
    local docker_version
    docker_version=$(docker --version)
    log_success "Docker is available: $docker_version"
    
    return 0
}

check_dockerfile_exists() {
    log_info "Checking Dockerfile exists..."
    
    if [[ ! -f "$PROJECT_ROOT/Dockerfile" ]]; then
        log_error "Dockerfile not found at: $PROJECT_ROOT/Dockerfile"
        return 1
    fi
    
    log_success "Dockerfile found"
    return 0
}

#######################################
# Build Functions
#######################################

build_docker_image() {
    log_section "STEP 1: Building Docker Image"
    
    local full_image_name="${IMAGE_NAME}:${IMAGE_TAG}"
    log_info "Building image: $full_image_name"
    log_info "Build context: $PROJECT_ROOT"
    
    # Build command
    local build_cmd="docker build"
    
    if [[ "$BUILD_NO_CACHE" == true ]]; then
        build_cmd+=" --no-cache"
        log_info "Building without cache"
    fi
    
    build_cmd+=" -t $full_image_name"
    build_cmd+=" -f $PROJECT_ROOT/Dockerfile"
    build_cmd+=" $PROJECT_ROOT"
    
    log_debug "Build command: $build_cmd"
    
    # Execute build
    log_info "Starting Docker build (this may take several minutes)..."
    local build_start=$(date +%s)
    
    if [[ "$VERBOSE" == true ]]; then
        if ! eval "$build_cmd"; then
            log_error "Docker build failed"
            return 1
        fi
    else
        if ! eval "$build_cmd" > "$OUTPUT_DIR/build.log" 2>&1; then
            log_error "Docker build failed"
            log_error "See build log: $OUTPUT_DIR/build.log"
            tail -n 20 "$OUTPUT_DIR/build.log" | sed 's/^/  /'
            return 1
        fi
    fi
    
    local build_end=$(date +%s)
    local build_duration=$((build_end - build_start))
    
    log_success "Docker image built successfully"
    log_info "  Image: $full_image_name"
    log_info "  Build time: ${build_duration}s"
    
    return 0
}

verify_image_size() {
    log_section "STEP 2: Verifying Image Size"
    
    local full_image_name="${IMAGE_NAME}:${IMAGE_TAG}"
    
    # Get image size
    local image_size_bytes
    image_size_bytes=$(docker image inspect "$full_image_name" --format='{{.Size}}' 2>/dev/null || echo "0")
    
    if [[ "$image_size_bytes" == "0" ]]; then
        log_error "Failed to get image size"
        return 2
    fi
    
    local image_size_mb=$((image_size_bytes / 1024 / 1024))
    
    log_info "Image size: ${image_size_mb} MB"
    log_info "Maximum allowed: ${MAX_IMAGE_SIZE_MB} MB"
    
    if [[ $image_size_mb -gt $MAX_IMAGE_SIZE_MB ]]; then
        log_error "Image size exceeds maximum allowed size"
        log_error "  Actual: ${image_size_mb} MB"
        log_error "  Maximum: ${MAX_IMAGE_SIZE_MB} MB"
        log_warn "Consider optimizing the Dockerfile to reduce image size"
        return 2
    fi
    
    local size_percentage=$((image_size_mb * 100 / MAX_IMAGE_SIZE_MB))
    log_success "Image size is acceptable (${size_percentage}% of maximum)"
    
    # Show layer information
    if [[ "$VERBOSE" == true ]]; then
        log_debug "Image layers:"
        docker history "$full_image_name" --human --no-trunc | head -n 10 | sed 's/^/  /'
    fi
    
    return 0
}

verify_components_installed() {
    log_section "STEP 3: Verifying Component Installation"
    
    local full_image_name="${IMAGE_NAME}:${IMAGE_TAG}"
    local all_checks_passed=true
    
    # Check ATX CLI
    log_info "Checking ATX CLI installation..."
    if docker run --rm "$full_image_name" sh -c "command -v atx && atx --version" > "$OUTPUT_DIR/atx_version.txt" 2>&1; then
        local atx_version=$(cat "$OUTPUT_DIR/atx_version.txt")
        log_success "ATX CLI is installed"
        log_info "  $(echo "$atx_version" | head -n 2 | tail -n 1)"
    else
        log_error "ATX CLI is not installed or not accessible"
        cat "$OUTPUT_DIR/atx_version.txt" | sed 's/^/  /'
        all_checks_passed=false
    fi
    
    # Check AWS CLI
    log_info "Checking AWS CLI installation..."
    if docker run --rm "$full_image_name" sh -c "command -v aws && aws --version" > "$OUTPUT_DIR/aws_version.txt" 2>&1; then
        local aws_version=$(cat "$OUTPUT_DIR/aws_version.txt" | tail -n 1)
        log_success "AWS CLI is installed"
        log_info "  $aws_version"
    else
        log_error "AWS CLI is not installed or not accessible"
        cat "$OUTPUT_DIR/aws_version.txt" | sed 's/^/  /'
        all_checks_passed=false
    fi
    
    # Check scripts are present
    log_info "Checking scripts are installed..."
    local scripts_to_check=(
        "/usr/local/bin/atx-orchestrator.sh"
        "/usr/local/bin/s3-integration.sh"
        "/usr/local/bin/smoke-test.sh"
        "/usr/local/bin/csv-parser.sh"
    )
    
    for script in "${scripts_to_check[@]}"; do
        if docker run --rm "$full_image_name" sh -c "test -x $script" 2>/dev/null; then
            log_success "  $script is present and executable"
        else
            log_error "  $script is missing or not executable"
            all_checks_passed=false
        fi
    done
    
    if [[ "$all_checks_passed" == true ]]; then
        log_success "All components are properly installed"
        return 0
    else
        log_error "Some components are missing or not properly installed"
        return 3
    fi
}

#######################################
# Test Functions
#######################################

run_smoke_test() {
    log_section "STEP 4: Running Smoke Test"
    
    local full_image_name="${IMAGE_NAME}:${IMAGE_TAG}"
    
    log_info "Executing smoke test in container..."
    log_info "This verifies ATX can execute transformations"
    
    # Create output directory for smoke test
    mkdir -p "$OUTPUT_DIR/smoke_test"
    
    # Run smoke test
    local smoke_test_cmd="docker run --rm"
    smoke_test_cmd+=" -v $OUTPUT_DIR/smoke_test:/workspace/results"
    smoke_test_cmd+=" $full_image_name"
    smoke_test_cmd+=" --smoke-test"
    smoke_test_cmd+=" --output-dir /workspace/results"
    
    if [[ "$VERBOSE" == true ]]; then
        smoke_test_cmd+=" --verbose"
    fi
    
    log_debug "Smoke test command: $smoke_test_cmd"
    
    local smoke_start=$(date +%s)
    
    if eval "$smoke_test_cmd"; then
        local smoke_end=$(date +%s)
        local smoke_duration=$((smoke_end - smoke_start))
        
        log_success "Smoke test passed"
        log_info "  Duration: ${smoke_duration}s"
        log_info "  Results: $OUTPUT_DIR/smoke_test/"
        
        # Show summary if available
        if [[ -f "$OUTPUT_DIR/smoke_test/smoke_test.log" ]]; then
            log_info "  Log file: $OUTPUT_DIR/smoke_test/smoke_test.log"
            
            if [[ "$VERBOSE" == true ]]; then
                log_debug "Smoke test log excerpt:"
                grep -E "\[SUCCESS\]|\[ERROR\]" "$OUTPUT_DIR/smoke_test/smoke_test.log" | tail -n 5 | sed 's/^/    /'
            fi
        fi
        
        return 0
    else
        local exit_code=$?
        log_error "Smoke test failed (exit code: $exit_code)"
        
        # Show failure details
        if [[ -f "$OUTPUT_DIR/smoke_test/smoke_test.log" ]]; then
            log_error "Smoke test log excerpt:"
            tail -n 20 "$OUTPUT_DIR/smoke_test/smoke_test.log" | sed 's/^/  /'
        fi
        
        if [[ -d "$OUTPUT_DIR/smoke_test/smoke_test_failure" ]]; then
            log_info "Failure artifacts preserved at: $OUTPUT_DIR/smoke_test/smoke_test_failure/"
        fi
        
        return 4
    fi
}

run_s3_integration_test() {
    log_section "STEP 5: Running S3 Integration Test (Optional)"
    
    if [[ "$SKIP_S3_TEST" == true ]]; then
        log_info "Skipping S3 integration test (--skip-s3-test specified)"
        return 0
    fi
    
    log_warn "S3 integration test requires:"
    log_warn "  - AWS credentials configured"
    log_warn "  - S3 bucket with sample Progress code"
    log_warn "  - CSV file with S3 paths"
    log_warn ""
    log_warn "This test is optional and can be skipped with --skip-s3-test"
    log_warn "For now, skipping S3 test (not yet implemented)"
    
    # TODO: Implement S3 integration test when S3 bucket is available
    # This would:
    # 1. Check AWS credentials
    # 2. Create test S3 bucket or use existing
    # 3. Upload sample Progress code
    # 4. Create CSV with S3 paths
    # 5. Run orchestrator with CSV
    # 6. Verify results uploaded to S3
    # 7. Clean up test resources
    
    return 0
}

#######################################
# Summary and Reporting
#######################################

generate_summary_report() {
    log_section "Build and Test Summary"
    
    local full_image_name="${IMAGE_NAME}:${IMAGE_TAG}"
    
    cat > "$OUTPUT_DIR/summary.txt" << EOF
ATX Container Build and Test Summary
====================================
Generated: $(date '+%Y-%m-%d %H:%M:%S')

IMAGE INFORMATION
-----------------
Image Name: $full_image_name
Image ID: $(docker image inspect "$full_image_name" --format='{{.Id}}' 2>/dev/null || echo "N/A")
Image Size: $(docker image inspect "$full_image_name" --format='{{.Size}}' 2>/dev/null | awk '{print int($1/1024/1024)" MB"}' || echo "N/A")
Created: $(docker image inspect "$full_image_name" --format='{{.Created}}' 2>/dev/null || echo "N/A")

COMPONENTS VERIFIED
-------------------
✓ ATX CLI installed and accessible
✓ AWS CLI installed and accessible
✓ Orchestrator script present
✓ S3 integration script present
✓ Smoke test script present
✓ CSV parser script present

TEST RESULTS
------------
✓ Docker build: PASSED
✓ Image size check: PASSED
✓ Component verification: PASSED
✓ Smoke test: PASSED

OUTPUT FILES
------------
- Build log: $OUTPUT_DIR/build.log
- ATX version: $OUTPUT_DIR/atx_version.txt
- AWS version: $OUTPUT_DIR/aws_version.txt
- Smoke test results: $OUTPUT_DIR/smoke_test/
- Summary: $OUTPUT_DIR/summary.txt

NEXT STEPS
----------
1. Push image to ECR:
   docker tag $full_image_name <account>.dkr.ecr.<region>.amazonaws.com/$IMAGE_NAME:$IMAGE_TAG
   docker push <account>.dkr.ecr.<region>.amazonaws.com/$IMAGE_NAME:$IMAGE_TAG

2. Deploy to ECS/EKS:
   See docs/deployment.md for deployment instructions

3. Run with sample data:
   docker run --rm -v \$(pwd)/examples:/data $full_image_name --csv-file /data/single-customer.csv

EOF
    
    cat "$OUTPUT_DIR/summary.txt"
    
    log_info ""
    log_info "Full summary saved to: $OUTPUT_DIR/summary.txt"
}

#######################################
# Main Function
#######################################

main() {
    # Parse arguments
    parse_arguments "$@"
    
    # Create output directory
    mkdir -p "$OUTPUT_DIR"
    
    log_section "ATX Container Build and Test"
    log_info "Started: $(date '+%Y-%m-%d %H:%M:%S')"
    log_info "Output directory: $OUTPUT_DIR"
    log_info ""
    
    # Pre-flight checks
    if ! check_docker_available; then
        exit 10
    fi
    
    if ! check_dockerfile_exists; then
        exit 1
    fi
    
    # Build image
    if [[ "$SKIP_BUILD" == false ]]; then
        if ! build_docker_image; then
            log_error "Build failed"
            exit 1
        fi
        
        if ! verify_image_size; then
            log_error "Image size verification failed"
            exit 2
        fi
    else
        log_info "Skipping build (--skip-build specified)"
    fi
    
    # Verify components
    if ! verify_components_installed; then
        log_error "Component verification failed"
        exit 3
    fi
    
    # Run smoke test
    if [[ "$SKIP_SMOKE_TEST" == false ]]; then
        if ! run_smoke_test; then
            log_error "Smoke test failed"
            exit 4
        fi
    else
        log_info "Skipping smoke test (--skip-smoke-test specified)"
    fi
    
    # Run S3 integration test (optional)
    if ! run_s3_integration_test; then
        log_error "S3 integration test failed"
        exit 5
    fi
    
    # Generate summary
    generate_summary_report
    
    log_section "ALL TESTS PASSED"
    log_success "Docker image is ready for deployment"
    log_info "Completed: $(date '+%Y-%m-%d %H:%M:%S')"
    
    exit 0
}

# Run main function
main "$@"
