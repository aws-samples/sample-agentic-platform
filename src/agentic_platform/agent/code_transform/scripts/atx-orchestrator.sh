#!/bin/bash
# ATX Orchestration Script
# Orchestrates batch processing of ATX transformations on S3-stored code folders
#
# This script:
# - Parses CSV configuration with S3 paths
# - Downloads folders from S3
# - Executes ATX transformations
# - Uploads results back to S3
# - Supports both serial and parallel execution modes
#
# Requirements: 1.3, 1.4, 1.5, 2.5, 4.1, 4.2, 4.3, 4.4, 6.1, 6.2, 6.3, 6.4

set -euo pipefail

#######################################
# Script Configuration
#######################################
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT_NAME=$(basename "$0")

# Source required scripts
source "$SCRIPT_DIR/s3-integration.sh"
source "$SCRIPT_DIR/csv-parser.sh"

#######################################
# Default Configuration
#######################################
DEFAULT_OUTPUT_DIR="./orchestrator_results"
DEFAULT_TEMP_BASE="/tmp/atx-orchestrator"
DEFAULT_MAX_PARALLEL_JOBS=4
DEFAULT_LOG_LEVEL="INFO"
DEFAULT_ATX_TIMEOUT=3600  # 1 hour per transformation
DEFAULT_PRESERVE_ON_FAILURE=true  # Preserve workspace and logs on failure

#######################################
# Global Variables
#######################################
CSV_FILE=""
OUTPUT_DIR="$DEFAULT_OUTPUT_DIR"
TEMP_BASE="$DEFAULT_TEMP_BASE"
EXECUTION_MODE="serial"
MAX_PARALLEL_JOBS="$DEFAULT_MAX_PARALLEL_JOBS"
LOG_LEVEL="$DEFAULT_LOG_LEVEL"
ATX_TIMEOUT="$DEFAULT_ATX_TIMEOUT"
VERBOSE=false
QUIET=false
SMOKE_TEST=false
DRY_RUN=false
PRESERVE_ON_FAILURE="$DEFAULT_PRESERVE_ON_FAILURE"

# Failure preservation tracking
declare -a FAILED_WORKSPACES=()
declare -a FAILED_LOGS=()

# Results tracking
declare -a PROCESSING_RESULTS=()
declare -a PROCESSING_PIDS=()
TOTAL_PROCESSED=0
TOTAL_SUCCESS=0
TOTAL_FAILED=0

# Timing
START_TIME=$(date +%s)

#######################################
# Usage and Help
#######################################

usage() {
    cat << EOF
ATX Orchestration Script

USAGE:
    $SCRIPT_NAME [OPTIONS] --csv-file <file>

REQUIRED:
    --csv-file <file>           CSV file with S3 paths and transformation configs

OPTIONS:
    --output-dir <dir>          Output directory for results (default: $DEFAULT_OUTPUT_DIR)
    --temp-base <dir>           Base directory for temp files (default: $DEFAULT_TEMP_BASE)
    --mode <serial|parallel>    Execution mode (default: serial)
    --max-jobs <n>              Max parallel jobs (default: $DEFAULT_MAX_PARALLEL_JOBS)
    --atx-timeout <seconds>     Timeout per ATX transformation (default: $DEFAULT_ATX_TIMEOUT)
    --log-level <level>         Log level: DEBUG, INFO, WARN, ERROR (default: $DEFAULT_LOG_LEVEL)
    --verbose                   Enable verbose output
    --quiet                     Suppress non-essential output
    --smoke-test                Run smoke test only
    --dry-run                   Show what would be executed without running
    --preserve-failures         Preserve workspace and logs on failure (default: true)
    --no-preserve-failures      Clean up workspace even on failure
    --help                      Show this help message

CSV FORMAT:
    s3_path,build_command,transformation_name,output_s3_path
    
    - s3_path: S3 path to folder with code (e.g., s3://bucket/customer1/folder1/)
    - build_command: Build command (typically "noop" for Progress analysis)
    - transformation_name: ATX transformation to apply
    - output_s3_path: S3 path for results (optional, defaults to results bucket)

EXAMPLES:
    # Serial execution
    $SCRIPT_NAME --csv-file repos.csv
    
    # Parallel execution with 8 jobs
    $SCRIPT_NAME --csv-file repos.csv --mode parallel --max-jobs 8
    
    # Verbose mode with custom output directory
    $SCRIPT_NAME --csv-file repos.csv --verbose --output-dir ./my_results
    
    # Smoke test to verify container setup
    $SCRIPT_NAME --smoke-test
    
    # Dry run to see what would be executed
    $SCRIPT_NAME --csv-file repos.csv --dry-run

ENVIRONMENT VARIABLES:
    LOG_LEVEL                   Override default log level
    TEMP_BASE_DIR               Override temp base directory
    MAX_RETRIES                 S3 operation retry count (default: 3)
    RETRY_DELAY                 Delay between retries in seconds (default: 5)

EOF
}

#######################################
# Logging Functions
#######################################

# Enhanced logging with quiet mode support
log_info() {
    if [[ "$QUIET" != true ]]; then
        log "INFO" "$@"
    fi
}

log_success() {
    if [[ "$QUIET" != true ]]; then
        echo -e "\033[0;32m[SUCCESS]\033[0m $*" >&2
    fi
}

log_progress() {
    if [[ "$QUIET" != true && "$VERBOSE" == true ]]; then
        echo -e "\033[0;36m[PROGRESS]\033[0m $*" >&2
    fi
}

#######################################
# Argument Parsing
#######################################

parse_arguments() {
    # Filter out script path if it appears as first argument (container issue workaround)
    if [[ $# -gt 0 && "$1" == "/usr/local/bin/atx-orchestrator.sh" ]]; then
        shift
    fi
    
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --csv-file)
                CSV_FILE="$2"
                shift 2
                ;;
            --output-dir)
                OUTPUT_DIR="$2"
                shift 2
                ;;
            --temp-base)
                TEMP_BASE="$2"
                shift 2
                ;;
            --mode)
                EXECUTION_MODE="$2"
                if [[ "$EXECUTION_MODE" != "serial" && "$EXECUTION_MODE" != "parallel" ]]; then
                    die "Invalid execution mode: $EXECUTION_MODE. Must be 'serial' or 'parallel'" 1
                fi
                shift 2
                ;;
            --max-jobs)
                MAX_PARALLEL_JOBS="$2"
                if ! [[ "$MAX_PARALLEL_JOBS" =~ ^[1-9][0-9]*$ ]]; then
                    die "Invalid --max-jobs value: $MAX_PARALLEL_JOBS. Must be a positive integer" 1
                fi
                shift 2
                ;;
            --atx-timeout)
                ATX_TIMEOUT="$2"
                if ! [[ "$ATX_TIMEOUT" =~ ^[0-9]+$ ]]; then
                    die "Invalid --atx-timeout value: $ATX_TIMEOUT. Must be a non-negative integer" 1
                fi
                shift 2
                ;;
            --log-level)
                LOG_LEVEL="$2"
                shift 2
                ;;
            --verbose)
                VERBOSE=true
                LOG_LEVEL="DEBUG"
                shift
                ;;
            --quiet)
                QUIET=true
                LOG_LEVEL="ERROR"
                shift
                ;;
            --smoke-test)
                SMOKE_TEST=true
                shift
                ;;
            --dry-run)
                DRY_RUN=true
                shift
                ;;
            --preserve-failures)
                PRESERVE_ON_FAILURE=true
                shift
                ;;
            --no-preserve-failures)
                PRESERVE_ON_FAILURE=false
                shift
                ;;
            --help|-h)
                usage
                exit 0
                ;;
            *)
                die "Unknown option: $1" 1
                ;;
        esac
    done
    
    # Validate required arguments (unless smoke test)
    if [[ "$SMOKE_TEST" != true ]]; then
        if [[ -z "$CSV_FILE" ]]; then
            die "Missing required argument: --csv-file" 1
        fi
        
        # Handle S3 CSV files by downloading them locally
        if [[ "$CSV_FILE" =~ ^s3:// ]]; then
            log_info "Downloading CSV file from S3: $CSV_FILE"
            local local_csv="/tmp/$(basename "$CSV_FILE")"
            if ! aws s3 cp "$CSV_FILE" "$local_csv"; then
                die "Failed to download CSV file from S3: $CSV_FILE" 1
            fi
            CSV_FILE="$local_csv"
            log_info "CSV file downloaded to: $CSV_FILE"
        elif [[ ! -f "$CSV_FILE" ]]; then
            die "CSV file not found: $CSV_FILE" 1
        fi
    fi
}

#######################################
# Initialization
#######################################

initialize_environment() {
    log_info "Initializing orchestration environment"
    
    # Export log level for sourced scripts
    export LOG_LEVEL="$LOG_LEVEL"
    export TEMP_BASE_DIR="$TEMP_BASE"
    
    # Create output directory
    mkdir -p "$OUTPUT_DIR"
    
    # Create temp base directory
    mkdir -p "$TEMP_BASE"
    
    # Initialize results file
    local results_file="$OUTPUT_DIR/results.json"
    echo '{"summary":{},"tests":[]}' > "$results_file"
    
    # Initialize summary log with detailed configuration
    local summary_log="$OUTPUT_DIR/summary.log"
    {
        echo "========================================"
        echo "ATX Container Test Execution Summary"
        echo "========================================"
        echo ""
        echo "CONFIGURATION"
        echo "-------------"
        echo "Started at: $(date '+%Y-%m-%d %H:%M:%S %Z')"
        echo "Start Timestamp: $START_TIME"
        echo "CSV file: $CSV_FILE"
        echo "Execution mode: $EXECUTION_MODE"
        echo "Max parallel jobs: $MAX_PARALLEL_JOBS"
        echo "ATX timeout: ${ATX_TIMEOUT}s"
        echo "Log level: $LOG_LEVEL"
        echo "Output directory: $OUTPUT_DIR"
        echo "Temp base directory: $TEMP_BASE"
        echo "Verbose: $VERBOSE"
        echo "Quiet: $QUIET"
        echo "Dry run: $DRY_RUN"
        echo ""
        echo "ENVIRONMENT"
        echo "-----------"
        echo "Hostname: $(hostname)"
        echo "User: $(whoami)"
        echo "Working directory: $(pwd)"
        echo "ATX version: $(atx --version 2>&1 || echo 'not found')"
        echo "AWS CLI version: $(aws --version 2>&1 || echo 'not found')"
        echo ""
        echo "EXECUTION LOG"
        echo "-------------"
        echo ""
    } > "$summary_log"
    
    log_info "Environment initialized successfully"
}


#######################################
# Single Folder Processing Function
# Requirements: 1.3, 1.4, 1.5
#######################################

process_single_folder() {
    local s3_path="$1"
    local build_command="$2"
    local transformation_name="$3"
    local output_s3_path="$4"
    local folder_index="$5"
    
    local folder_name=$(basename "$s3_path")
    local folder_id="${folder_name}_${folder_index}"
    local start_time=$(date +%s)
    
    log_info "Processing folder $folder_index: $folder_name"
    log_debug "S3 path: $s3_path"
    log_debug "Build command: $build_command"
    log_debug "Transformation: $transformation_name"
    log_debug "Output S3 path: $output_s3_path"
    
    # Create workspace for this folder
    local workspace="$TEMP_BASE/workspace_${folder_id}"
    local results_dir="$TEMP_BASE/results_${folder_id}"
    # Ensure OUTPUT_DIR is absolute path
    local abs_output_dir
    if [[ "$OUTPUT_DIR" = /* ]]; then
        abs_output_dir="$OUTPUT_DIR"
    else
        abs_output_dir="$(pwd)/$OUTPUT_DIR"
    fi
    
    local log_file="$abs_output_dir/${folder_id}_execution.log"
    
    mkdir -p "$workspace"
    mkdir -p "$results_dir"
    mkdir -p "$abs_output_dir"
    
    # Debug log file creation
    log_debug "Creating log file: $log_file"
    log_debug "Working directory: $(pwd)"
    log_debug "Output directory: $abs_output_dir"
    
    # Initialize per-folder execution log with detailed metadata
    {
        echo "========================================"
        echo "ATX Transformation Execution Log"
        echo "========================================"
        echo ""
        echo "METADATA"
        echo "--------"
        echo "Folder ID: $folder_id"
        echo "Folder Name: $folder_name"
        echo "Folder Index: $folder_index"
        echo "S3 Source Path: $s3_path"
        echo "S3 Output Path: $output_s3_path"
        echo "Transformation: $transformation_name"
        echo "Build Command: $build_command"
        echo "Started: $(date '+%Y-%m-%d %H:%M:%S %Z')"
        echo "Start Timestamp: $start_time"
        echo "Workspace: $workspace"
        echo "Results Directory: $results_dir"
        echo "Log File: $log_file"
        echo ""
        echo "EXECUTION LOG"
        echo "-------------"
        echo ""
    } > "$log_file" 2>&1
    
    # Verify log file was created
    if [[ ! -f "$log_file" ]]; then
        log_error "Failed to create log file: $log_file"
        log_error "Directory permissions: $(ls -ld "$abs_output_dir" 2>/dev/null || echo 'Directory does not exist')"
        # Create a fallback log file in /tmp
        log_file="/tmp/${folder_id}_execution.log"
        log_warn "Using fallback log file: $log_file"
        {
            echo "========================================"
            echo "ATX Transformation Execution Log (FALLBACK)"
            echo "========================================"
            echo "Original log file failed: $abs_output_dir/${folder_id}_execution.log"
            echo ""
        } > "$log_file"
    fi
    
    local exit_code=0
    local status="SUCCESS"
    local message="Transformation completed"
    
    # Step 1: Download folder from S3
    {
        echo "[$(date '+%Y-%m-%d %H:%M:%S')] STEP 1: Downloading folder from S3"
        echo "Source: $s3_path"
        echo "Destination: $workspace"
    } >> "$log_file"
    
    log_progress "Downloading folder from S3: $s3_path"
    
    if ! s3_download "$s3_path" "$workspace" >> "$log_file" 2>&1; then
        exit_code=$?
        status="FAILED"
        message="S3 download failed (exit code: $exit_code)"
        log_error "Failed to download folder from S3: $s3_path"
        
        {
            echo "[$(date '+%Y-%m-%d %H:%M:%S')] ERROR: S3 download failed"
            echo "Exit code: $exit_code"
            echo "Status: $status"
        } >> "$log_file"
    else
        {
            echo "[$(date '+%Y-%m-%d %H:%M:%S')] SUCCESS: S3 download completed"
        } >> "$log_file"
        
        # Initialize Git repository (required by ATX)
        {
            echo ""
            echo "[$(date '+%Y-%m-%d %H:%M:%S')] STEP 1.5: Initializing Git repository"
            echo "ATX requires the code repository to be managed by Git"
        } >> "$log_file"
        
        log_progress "Initializing Git repository in workspace"
        
        if cd "$workspace" && git init --quiet && git config user.name "ATX Orchestrator" && git config user.email "atx@example.com" && git add . && git commit -m "Initial commit for ATX transformation" --quiet; then
            {
                echo "[$(date '+%Y-%m-%d %H:%M:%S')] SUCCESS: Git repository initialized"
            } >> "$log_file"
        else
            exit_code=$?
            status="FAILED"
            message="Git initialization failed (exit code: $exit_code)"
            log_error "Failed to initialize Git repository in workspace: $workspace"
            {
                echo "[$(date '+%Y-%m-%d %H:%M:%S')] ERROR: Git initialization failed"
                echo "Exit code: $exit_code"
            } >> "$log_file"
        fi
    fi
    
    # Step 2: Execute ATX transformation (if download and git init succeeded)
    if [[ $exit_code -eq 0 ]]; then
        {
            echo ""
            echo "[$(date '+%Y-%m-%d %H:%M:%S')] STEP 2: Executing ATX transformation"
            echo "Transformation: $transformation_name"
            echo "Build command: $build_command"
            echo "Workspace: $workspace"
            echo "Timeout: ${ATX_TIMEOUT}s"
        } >> "$log_file"
        
        log_progress "Executing ATX transformation: $transformation_name"
        
        if [[ "$DRY_RUN" == true ]]; then
            echo "[$(date '+%Y-%m-%d %H:%M:%S')] DRY RUN: Would execute ATX transformation" >> "$log_file"
            log_info "DRY RUN: Skipping actual ATX execution"
        else
            # Execute ATX transformation with timeout
            local atx_cmd="atx custom def exec"
            atx_cmd+=" --code-repository-path \"$workspace\""
            atx_cmd+=" --transformation-name \"$transformation_name\""
            atx_cmd+=" --build-command \"$build_command\""
            atx_cmd+=" --non-interactive"
            atx_cmd+=" --trust-all-tools"
            
            {
                echo ""
                echo "Command: $atx_cmd"
                echo "----------------------------------------"
            } >> "$log_file"
            
            # Use timeout if available
            local timeout_cmd=""
            if command -v timeout &> /dev/null; then
                timeout_cmd="timeout $ATX_TIMEOUT"
            fi
            
            # Execute and capture exit code with detailed error handling
            local atx_start=$(date +%s)
            local atx_output
            if atx_output=$(eval "$timeout_cmd $atx_cmd" 2>&1); then
                local atx_end=$(date +%s)
                local atx_duration=$((atx_end - atx_start))
                
                echo "$atx_output" >> "$log_file"
                {
                    echo "----------------------------------------"
                    echo "[$(date '+%Y-%m-%d %H:%M:%S')] SUCCESS: ATX transformation completed"
                    echo "Duration: ${atx_duration}s"
                } >> "$log_file"
                
                log_success "ATX transformation completed for folder: $folder_name (${atx_duration}s)"
                
                # Copy ATX output to results directory
                if [[ -d "$workspace" ]]; then
                    local files_copied=0
                    files_copied=$(find "$workspace" -name "*.md" -exec cp {} "$results_dir/" \; -print 2>/dev/null | wc -l)
                    echo "[$(date '+%Y-%m-%d %H:%M:%S')] Copied $files_copied markdown files to results" >> "$log_file"
                    
                    files_copied=$(find "$workspace" -name "*.log" -exec cp {} "$results_dir/" \; -print 2>/dev/null | wc -l)
                    echo "[$(date '+%Y-%m-%d %H:%M:%S')] Copied $files_copied log files to results" >> "$log_file"
                    
                    files_copied=$(find "$workspace" -name "*.json" -exec cp {} "$results_dir/" \; -print 2>/dev/null | wc -l)
                    echo "[$(date '+%Y-%m-%d %H:%M:%S')] Copied $files_copied JSON files to results" >> "$log_file"
                fi
            else
                exit_code=$?
                local atx_end=$(date +%s)
                local atx_duration=$((atx_end - atx_start))
                
                echo "$atx_output" >> "$log_file"
                {
                    echo "----------------------------------------"
                    echo "[$(date '+%Y-%m-%d %H:%M:%S')] FAILED: ATX transformation failed"
                    echo "Duration: ${atx_duration}s"
                } >> "$log_file"
                
                status="FAILED"
                
                # Detailed error analysis
                if [[ $exit_code -eq 124 ]]; then
                    message="ATX execution timeout after ${ATX_TIMEOUT}s"
                    log_error "ATX execution timeout for folder: $folder_name"
                    log_error "Transformation exceeded maximum time limit of ${ATX_TIMEOUT}s"
                    log_error "Consider increasing --atx-timeout or checking for infinite loops"
                    echo "ERROR: Timeout after ${ATX_TIMEOUT}s" >> "$log_file"
                elif [[ $exit_code -eq 127 ]]; then
                    message="ATX command not found"
                    log_error "ATX CLI not found or not in PATH"
                    log_error "Verify ATX installation: atx --version"
                    echo "ERROR: ATX command not found" >> "$log_file"
                elif [[ $exit_code -eq 126 ]]; then
                    message="ATX command not executable"
                    log_error "ATX CLI found but not executable"
                    log_error "Check file permissions on ATX binary"
                    echo "ERROR: ATX not executable" >> "$log_file"
                else
                    message="ATX execution failed (exit code: $exit_code)"
                    log_error "ATX execution failed for folder: $folder_name (exit code: $exit_code)"
                    
                    # Analyze error output for common issues
                    if echo "$atx_output" | grep -qi "permission denied"; then
                        log_error "Permission denied - check file/directory permissions"
                        message="$message - Permission denied"
                    elif echo "$atx_output" | grep -qi "out of memory\|cannot allocate memory"; then
                        log_error "Out of memory - transformation requires more RAM"
                        log_error "Consider increasing container memory limits"
                        message="$message - Out of memory"
                    elif echo "$atx_output" | grep -qi "no such file\|file not found"; then
                        log_error "File not found - check code repository structure"
                        message="$message - File not found"
                    elif echo "$atx_output" | grep -qi "syntax error\|parse error"; then
                        log_error "Syntax/parse error in source code"
                        message="$message - Parse error"
                    elif echo "$atx_output" | grep -qi "network\|connection"; then
                        log_error "Network error during transformation"
                        log_error "Check internet connectivity if transformation requires external resources"
                        message="$message - Network error"
                    fi
                    
                    echo "ERROR: Exit code $exit_code" >> "$log_file"
                    echo "See log file for details: $log_file" >> "$log_file"
                fi
                
                # Preserve workspace for debugging on failure
                log_warn "Preserving workspace for debugging: $workspace"
                echo "Workspace preserved at: $workspace" >> "$log_file"
            fi
        fi
    fi
    
    # Step 3: Upload results to S3 (even if transformation failed, upload logs)
    if [[ "$DRY_RUN" != true ]]; then
        {
            echo ""
            echo "[$(date '+%Y-%m-%d %H:%M:%S')] STEP 3: Uploading results to S3"
        } >> "$log_file"
        
        log_progress "Uploading results to S3: $output_s3_path"
        
        # Copy execution log to results directory
        cp "$log_file" "$results_dir/"
        echo "[$(date '+%Y-%m-%d %H:%M:%S')] Execution log copied to results directory" >> "$log_file"
        
        # Determine output S3 path (use default if not specified)
        local final_output_path="$output_s3_path"
        if [[ -z "$final_output_path" ]]; then
            # Default: mirror source structure in results bucket
            final_output_path="${s3_path/source/results}"
            echo "[$(date '+%Y-%m-%d %H:%M:%S')] Using default output path: $final_output_path" >> "$log_file"
        fi
        
        {
            echo "Destination: $final_output_path"
            echo "Source: $results_dir"
        } >> "$log_file"
        
        # Upload results
        if ! s3_upload_results "$results_dir" "$final_output_path" >> "$log_file" 2>&1; then
            log_warn "Failed to upload results to S3: $final_output_path"
            {
                echo "[$(date '+%Y-%m-%d %H:%M:%S')] WARNING: S3 upload failed"
            } >> "$log_file"
            
            # Don't change status if transformation succeeded
            if [[ "$status" == "SUCCESS" ]]; then
                status="SUCCESS_WITH_WARNINGS"
                message="Transformation completed but upload had issues"
            fi
        else
            log_progress "Results uploaded successfully to: $final_output_path"
            {
                echo "[$(date '+%Y-%m-%d %H:%M:%S')] SUCCESS: Results uploaded to S3"
            } >> "$log_file"
        fi
    fi
    
    # Step 4: Cleanup temp files with failure preservation
    {
        echo ""
        echo "[$(date '+%Y-%m-%d %H:%M:%S')] STEP 4: Cleaning up temporary files"
    } >> "$log_file"
    
    log_progress "Cleaning up temporary files"
    
    # Calculate duration for reporting
    local end_time=$(date +%s)
    local duration=$((end_time - start_time))
    
    # Preserve workspace and logs on failure if configured
    if [[ "$status" == "FAILED" && "$PRESERVE_ON_FAILURE" == true ]]; then
        log_warn "Preserving workspace for debugging: $workspace"
        
        # Create a failure preservation directory
        local failure_dir="$abs_output_dir/failures/${folder_id}"
        mkdir -p "$failure_dir"
        
        # Copy workspace to failure directory for debugging
        if [[ -d "$workspace" ]]; then
            log_info "Copying workspace to failure directory: $failure_dir"
            cp -r "$workspace" "$failure_dir/workspace" 2>/dev/null || true
            echo "[$(date '+%Y-%m-%d %H:%M:%S')] Workspace preserved at: $failure_dir/workspace" >> "$log_file"
        fi
        
        # Copy execution log to failure directory
        cp "$log_file" "$failure_dir/execution.log" 2>/dev/null || true
        echo "[$(date '+%Y-%m-%d %H:%M:%S')] Execution log preserved at: $failure_dir/execution.log" >> "$log_file"
        
        # Create a failure summary file
        {
            echo "FAILURE SUMMARY"
            echo "==============="
            echo "Folder: $folder_name"
            echo "Folder ID: $folder_id"
            echo "S3 Path: $s3_path"
            echo "Transformation: $transformation_name"
            echo "Status: $status"
            echo "Message: $message"
            echo "Exit Code: $exit_code"
            echo "Duration: ${duration}s"
            echo ""
            echo "PRESERVED ARTIFACTS"
            echo "==================="
            echo "Workspace: $failure_dir/workspace"
            echo "Execution log: $failure_dir/execution.log"
            echo "Original workspace: $workspace"
            echo "Original log: $log_file"
            echo ""
            echo "DEBUGGING STEPS"
            echo "==============="
            echo "1. Review execution log: cat $failure_dir/execution.log"
            echo "2. Inspect workspace: ls -la $failure_dir/workspace"
            echo "3. Check source files: find $failure_dir/workspace -type f"
            echo "4. Manually run ATX: cd $failure_dir/workspace && atx custom def exec ..."
            echo "5. Review S3 source: aws s3 ls $s3_path"
            echo ""
        } > "$failure_dir/README.txt"
        
        # Track failed workspace for summary
        FAILED_WORKSPACES+=("$failure_dir")
        FAILED_LOGS+=("$log_file")
        
        log_info "Failure artifacts preserved at: $failure_dir"
        echo "[$(date '+%Y-%m-%d %H:%M:%S')] Failure artifacts preserved at: $failure_dir" >> "$log_file"
        
        # Still cleanup the original workspace to save space (we have a copy)
        cleanup_safe "$workspace"
        echo "[$(date '+%Y-%m-%d %H:%M:%S')] Original workspace cleaned up (copy preserved)" >> "$log_file"
    elif [[ "$status" == "SUCCESS" || "$status" == "SUCCESS_WITH_WARNINGS" ]]; then
        cleanup_safe "$workspace"
        echo "[$(date '+%Y-%m-%d %H:%M:%S')] Workspace cleaned up: $workspace" >> "$log_file"
    else
        # Failure but preservation disabled
        log_info "Cleaning up workspace (preservation disabled)"
        cleanup_safe "$workspace"
        echo "[$(date '+%Y-%m-%d %H:%M:%S')] Workspace cleaned up: $workspace" >> "$log_file"
    fi
    
    cleanup_safe "$results_dir"
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] Results directory cleaned up: $results_dir" >> "$log_file"
    
    # Log completion with detailed status information
    {
        echo ""
        echo "========================================"
        echo "EXECUTION SUMMARY"
        echo "========================================"
        echo "Completed: $(date '+%Y-%m-%d %H:%M:%S %Z')"
        echo "End Timestamp: $end_time"
        echo "Duration: ${duration}s"
        echo "Status Code: $exit_code"
        echo "Status: $status"
        echo "Message: $message"
        echo ""
        
        # Add troubleshooting information for failures
        if [[ "$status" == "FAILED" ]]; then
            echo "TROUBLESHOOTING"
            echo "---------------"
            echo "1. Check the execution log above for error details"
            echo "2. Verify S3 paths are correct and accessible"
            echo "3. Ensure AWS credentials have proper permissions"
            echo "4. Check ATX transformation name is valid"
            echo "5. Review workspace contents: $workspace"
            echo ""
            echo "For S3 errors:"
            echo "  - Verify bucket exists and is accessible"
            echo "  - Check IAM permissions (s3:GetObject, s3:PutObject, s3:ListBucket)"
            echo "  - Ensure network connectivity to S3"
            echo ""
            echo "For ATX errors:"
            echo "  - Verify ATX CLI is installed: atx --version"
            echo "  - Check transformation name is correct"
            echo "  - Review source code for syntax errors"
            echo "  - Check available memory and disk space"
            echo ""
        fi
        
        echo "Log file location: $log_file"
        echo "========================================"
    } >> "$log_file"
    
    # Return result
    echo "$status|$folder_name|$message|$duration|$log_file"
    return $exit_code
}

#######################################
# Serial Execution Mode
# Requirements: 2.5
#######################################

execute_serial() {
    log_info "Starting serial execution mode"
    
    local queue_size=$(get_queue_size)
    log_info "Processing $queue_size folders sequentially"
    
    local current=0
    
    # Process each folder one at a time
    while [[ $current -lt $queue_size ]]; do
        local item=$(get_queue_item "$current")
        
        # Parse item
        IFS='|' read -r s3_path build_cmd transform_name output_s3_path <<< "$item"
        
        log_info "Processing folder $((current + 1))/$queue_size"
        
        # Process folder and capture result
        local result
        if result=$(process_single_folder "$s3_path" "$build_cmd" "$transform_name" "$output_s3_path" "$current"); then
            TOTAL_SUCCESS=$((TOTAL_SUCCESS + 1))
        else
            TOTAL_FAILED=$((TOTAL_FAILED + 1))
        fi
        
        TOTAL_PROCESSED=$((TOTAL_PROCESSED + 1))
        PROCESSING_RESULTS+=("$result")
        
        current=$((current + 1))
    done
    
    log_success "Serial execution completed: $TOTAL_PROCESSED folders processed"
}

#######################################
# Parallel Execution Mode
# Requirements: 6.1, 6.2, 6.3, 6.4
#######################################

execute_parallel() {
    log_info "Starting parallel execution mode (max $MAX_PARALLEL_JOBS jobs)"
    
    local queue_size=$(get_queue_size)
    log_info "Processing $queue_size folders in parallel"
    
    local current=0
    local active_jobs=0
    
    # Process folders with parallel job limit
    while [[ $current -lt $queue_size ]] || [[ $active_jobs -gt 0 ]]; do
        # Start new jobs up to max limit
        while [[ $current -lt $queue_size ]] && [[ $active_jobs -lt $MAX_PARALLEL_JOBS ]]; do
            local item=$(get_queue_item "$current")
            
            # Parse item
            IFS='|' read -r s3_path build_cmd transform_name output_s3_path <<< "$item"
            
            log_info "Starting parallel job $((current + 1))/$queue_size"
            
            # Start background job and capture result
            (
                local result=$(process_single_folder "$s3_path" "$build_cmd" "$transform_name" "$output_s3_path" "$current")
                local exit_code=$?
                
                # Write result to temp file for parent process
                echo "$result" > "$TEMP_BASE/result_${current}.txt"
                echo "$exit_code" > "$TEMP_BASE/exitcode_${current}.txt"
            ) &
            
            local pid=$!
            PROCESSING_PIDS+=("$pid:$current")
            
            active_jobs=$((active_jobs + 1))
            current=$((current + 1))
        done
        
        # Wait for at least one job to complete
        if [[ $active_jobs -gt 0 ]]; then
            wait_for_job_completion
            active_jobs=${#PROCESSING_PIDS[@]}
        fi
    done
    
    log_success "Parallel execution completed: $TOTAL_PROCESSED folders processed"
}

# Wait for job completion in parallel mode
wait_for_job_completion() {
    local new_pids=()
    
    # Handle empty array case
    if [[ ${#PROCESSING_PIDS[@]} -eq 0 ]]; then
        return
    fi
    
    for pid_info in "${PROCESSING_PIDS[@]}"; do
        IFS=':' read -r pid index <<< "$pid_info"
        
        if kill -0 "$pid" 2>/dev/null; then
            # Job still running
            new_pids+=("$pid_info")
        else
            # Job completed
            wait "$pid" 2>/dev/null || true
            
            # Read result from job output files
            local result_file="$TEMP_BASE/result_${index}.txt"
            local exitcode_file="$TEMP_BASE/exitcode_${index}.txt"
            
            if [[ -f "$result_file" ]]; then
                local result=$(cat "$result_file")
                PROCESSING_RESULTS+=("$result")
                rm -f "$result_file"
            fi
            
            local job_exit_code=1
            if [[ -f "$exitcode_file" ]]; then
                job_exit_code=$(cat "$exitcode_file")
                rm -f "$exitcode_file"
            fi
            
            TOTAL_PROCESSED=$((TOTAL_PROCESSED + 1))
            
            if [[ $job_exit_code -eq 0 ]]; then
                TOTAL_SUCCESS=$((TOTAL_SUCCESS + 1))
            else
                TOTAL_FAILED=$((TOTAL_FAILED + 1))
            fi
            
            log_progress "Job completed: $((TOTAL_PROCESSED)) of $(get_queue_size)"
        fi
    done
    
    # Handle empty new_pids array
    if [[ ${#new_pids[@]} -gt 0 ]]; then
        PROCESSING_PIDS=("${new_pids[@]}")
    else
        PROCESSING_PIDS=()
    fi
    
    # If still at max capacity, sleep briefly
    if [[ ${#PROCESSING_PIDS[@]} -ge $MAX_PARALLEL_JOBS ]]; then
        sleep 1
    fi
}


#######################################
# Result Aggregation
# Requirements: 4.1, 4.2, 4.4, 6.4
#######################################

aggregate_results() {
    log_info "Aggregating results from all processed folders"
    
    local end_time=$(date +%s)
    local total_duration=$((end_time - START_TIME))
    
    # Recalculate statistics from actual results (in case parallel mode didn't update counters correctly)
    TOTAL_PROCESSED=${#PROCESSING_RESULTS[@]}
    TOTAL_SUCCESS=0
    TOTAL_FAILED=0
    
    for result in "${PROCESSING_RESULTS[@]}"; do
        IFS='|' read -r status folder_name message duration log_file <<< "$result"
        if [[ "$status" == "SUCCESS" || "$status" == "SUCCESS_WITH_WARNINGS" ]]; then
            TOTAL_SUCCESS=$((TOTAL_SUCCESS + 1))
        else
            TOTAL_FAILED=$((TOTAL_FAILED + 1))
        fi
    done
    
    # Calculate statistics
    local success_rate=0
    if [[ $TOTAL_PROCESSED -gt 0 ]]; then
        success_rate=$(( (TOTAL_SUCCESS * 100) / TOTAL_PROCESSED ))
    fi
    
    # Generate human-readable summary
    local summary_log="$OUTPUT_DIR/summary.log"
    {
        echo ""
        echo "EXECUTION SUMMARY"
        echo "================="
        echo "Execution completed at: $(date)"
        echo "Total wall time: ${total_duration}s"
        echo ""
        echo "STATISTICS TABLE"
        echo "=================="
        printf "%-25s | %-10s\n" "Metric" "Value"
        printf "%-25s-+-%-10s\n" "-------------------------" "----------"
        printf "%-25s | %-10s\n" "Total Folders" "$TOTAL_PROCESSED"
        printf "%-25s | %-10s\n" "Successful" "$TOTAL_SUCCESS"
        printf "%-25s | %-10s\n" "Failed" "$TOTAL_FAILED"
        printf "%-25s | %-10s%%\n" "Success Rate" "$success_rate"
        printf "%-25s | %-10s\n" "Execution Mode" "$EXECUTION_MODE"
        printf "%-25s | %-10s\n" "Max Parallel Jobs" "$MAX_PARALLEL_JOBS"
        echo ""
        
        if [[ $TOTAL_FAILED -gt 0 && ${#PROCESSING_RESULTS[@]} -gt 0 ]]; then
            echo "FAILED FOLDERS"
            echo "=============="
            for result in "${PROCESSING_RESULTS[@]}"; do
                IFS='|' read -r status folder_name message duration log_file <<< "$result"
                if [[ "$status" == "FAILED" ]]; then
                    printf "%-30s | %-40s | %s\n" "$folder_name" "$message" "$log_file"
                fi
            done
            echo ""
            
            # Add preserved failure information
            if [[ ${#FAILED_WORKSPACES[@]} -gt 0 ]]; then
                echo "PRESERVED FAILURE ARTIFACTS"
                echo "============================"
                echo "Failure preservation: $PRESERVE_ON_FAILURE"
                echo "Number of preserved failures: ${#FAILED_WORKSPACES[@]}"
                echo ""
                echo "Preserved workspace locations:"
                for workspace in "${FAILED_WORKSPACES[@]}"; do
                    echo "  - $workspace"
                done
                echo ""
                echo "To debug failures:"
                echo "  1. Navigate to preserved workspace directory"
                echo "  2. Review README.txt for debugging steps"
                echo "  3. Inspect execution.log for error details"
                echo "  4. Examine workspace/ directory for source files"
                echo ""
            fi
        fi
        
        echo "DETAILED RESULTS"
        echo "================"
        printf "%-10s | %-30s | %-40s | %-10s\n" "Status" "Folder" "Message" "Duration(s)"
        printf "%-10s-+-%-30s-+-%-40s-+-%-10s\n" "----------" "------------------------------" "----------------------------------------" "----------"
        if [[ ${#PROCESSING_RESULTS[@]} -gt 0 ]]; then
            for result in "${PROCESSING_RESULTS[@]}"; do
                IFS='|' read -r status folder_name message duration log_file <<< "$result"
                printf "%-10s | %-30s | %-40s | %-10s\n" "$status" "$folder_name" "$message" "$duration"
            done
        fi
        echo ""
        
        echo "LOG FILES"
        echo "========="
        echo "Summary log: $summary_log"
        echo "Individual logs: $OUTPUT_DIR/*_execution.log"
        echo "Results JSON: $OUTPUT_DIR/results.json"
        echo ""
        
    } >> "$summary_log"
    
    # Generate machine-readable JSON report
    generate_json_report "$total_duration"
    
    # Display summary to console
    if [[ "$QUIET" != true ]]; then
        echo ""
        echo "=========================================="
        echo "ORCHESTRATION COMPLETED"
        echo "=========================================="
        echo "Total folders: $TOTAL_PROCESSED"
        echo "Successful: $TOTAL_SUCCESS"
        echo "Failed: $TOTAL_FAILED"
        echo "Success rate: ${success_rate}%"
        echo "Total time: ${total_duration}s"
        echo ""
        echo "Full summary available at: $summary_log"
        echo "=========================================="
    fi
}

# Generate JSON report
generate_json_report() {
    local total_duration="$1"
    local results_file="$OUTPUT_DIR/results.json"
    
    # Calculate success rate
    local success_rate=0
    if [[ $TOTAL_PROCESSED -gt 0 ]]; then
        success_rate=$(( (TOTAL_SUCCESS * 100) / TOTAL_PROCESSED ))
    fi
    
    # Start JSON structure
    {
        echo "{"
        echo "  \"summary\": {"
        echo "    \"total\": $TOTAL_PROCESSED,"
        echo "    \"successful\": $TOTAL_SUCCESS,"
        echo "    \"failed\": $TOTAL_FAILED,"
        echo "    \"success_rate\": $success_rate,"
        echo "    \"execution_time\": $total_duration,"
        echo "    \"wall_time\": $total_duration,"
        echo "    \"execution_mode\": \"$EXECUTION_MODE\","
        echo "    \"max_parallel_jobs\": $MAX_PARALLEL_JOBS,"
        echo "    \"completed_at\": \"$(date -u +%Y-%m-%dT%H:%M:%SZ)\""
        echo "  },"
        echo "  \"tests\": ["
        
        # Add test results
        local first=true
        if [[ ${#PROCESSING_RESULTS[@]} -gt 0 ]]; then
            for result in "${PROCESSING_RESULTS[@]}"; do
                IFS='|' read -r status folder_name message duration log_file <<< "$result"
                
                if [[ "$first" == true ]]; then
                    first=false
                else
                    echo ","
                fi
                
                echo -n "    {"
                echo -n "\"name\": \"$folder_name\", "
                echo -n "\"status\": \"$status\", "
                echo -n "\"duration\": $duration, "
                echo -n "\"message\": \"$message\", "
                echo -n "\"log_file\": \"$log_file\""
                echo -n "}"
            done
        fi
        
        echo ""
        echo "  ]"
        echo "}"
    } > "$results_file"
    
    log_info "JSON report generated: $results_file"
}

#######################################
# Smoke Test Functionality
# Requirements: 10.1, 10.2, 10.3, 10.4
#######################################

run_smoke_test() {
    log_info "Running smoke test to verify container setup"
    
    local smoke_test_log="$OUTPUT_DIR/smoke_test.log"
    local smoke_test_script="$SCRIPT_DIR/smoke-test.sh"
    
    # Check if smoke test script exists
    if [[ ! -f "$smoke_test_script" ]]; then
        log_error "Smoke test script not found: $smoke_test_script"
        log_error "Expected location: scripts/smoke-test.sh"
        return 1
    fi
    
    # Make sure script is executable
    chmod +x "$smoke_test_script" 2>/dev/null || true
    
    # Run the smoke test script
    log_info "Executing smoke test script: $smoke_test_script"
    
    local smoke_args=(
        "--log-file" "$smoke_test_log"
        "--temp-dir" "$TEMP_BASE/smoke_test"
    )
    
    if [[ "$VERBOSE" == true ]]; then
        smoke_args+=("--verbose")
    fi
    
    if [[ "$PRESERVE_ON_FAILURE" == false ]]; then
        smoke_args+=("--no-preserve")
    fi
    
    # Execute smoke test
    if "$smoke_test_script" "${smoke_args[@]}"; then
        log_success "Smoke test passed"
        log_info "Container is properly configured for ATX transformations"
        log_info "Smoke test log: $smoke_test_log"
        return 0
    else
        local smoke_exit_code=$?
        log_error "Smoke test failed with exit code: $smoke_exit_code"
        log_error "See $smoke_test_log for details"
        
        # Preserve smoke test artifacts on failure (handled by smoke-test.sh)
        local smoke_failure_dir="$OUTPUT_DIR/smoke_test_failure"
        local smoke_test_dir="$TEMP_BASE/smoke_test"
        
        # Additional preservation if smoke test script didn't handle it
        if [[ "$PRESERVE_ON_FAILURE" == true && -d "$smoke_test_dir" ]]; then
            mkdir -p "$smoke_failure_dir"
            
            log_warn "Preserving smoke test artifacts for debugging"
            
            # Copy smoke test directory if not already preserved
            if [[ ! -d "$smoke_failure_dir/workspace" && -d "$smoke_test_dir" ]]; then
                cp -r "$smoke_test_dir" "$smoke_failure_dir/workspace" 2>/dev/null || true
                log_info "Smoke test workspace preserved at: $smoke_failure_dir/workspace"
            fi
            
            # Copy smoke test log if not already there
            if [[ ! -f "$smoke_failure_dir/smoke_test.log" && -f "$smoke_test_log" ]]; then
                cp "$smoke_test_log" "$smoke_failure_dir/smoke_test.log" 2>/dev/null || true
            fi
            
            # Create debugging guide if not already created
            if [[ ! -f "$smoke_failure_dir/README.txt" ]]; then
                {
                    echo "SMOKE TEST FAILURE"
                    echo "=================="
                    echo "The smoke test failed, indicating the container is not properly configured."
                    echo ""
                    echo "PRESERVED ARTIFACTS"
                    echo "==================="
                    echo "Workspace: $smoke_failure_dir/workspace"
                    echo "Log: $smoke_failure_dir/smoke_test.log"
                    echo ""
                    echo "DEBUGGING STEPS"
                    echo "==============="
                    echo "1. Review smoke test log: cat $smoke_failure_dir/smoke_test.log"
                    echo "2. Check ATX installation: atx --version"
                    echo "3. Check AWS CLI installation: aws --version"
                    echo "4. Verify test code: cat $smoke_failure_dir/workspace/test.p"
                    echo "5. Manually run ATX: cd $smoke_failure_dir/workspace && atx custom def exec ..."
                    echo ""
                    echo "COMMON ISSUES"
                    echo "============="
                    echo "- ATX CLI not installed or not in PATH"
                    echo "- AWS CLI not installed"
                    echo "- Missing dependencies (curl, git, python3)"
                    echo "- Incorrect ATX installation"
                    echo "- Network connectivity issues"
                    echo ""
                    echo "EXIT CODE MEANINGS"
                    echo "=================="
                    echo "1 - ATX CLI not found"
                    echo "2 - AWS CLI not found"
                    echo "3 - Failed to create test code"
                    echo "4 - ATX transformation failed"
                    echo "5 - General error"
                    echo ""
                } > "$smoke_failure_dir/README.txt"
            fi
            
            log_info "Smoke test failure artifacts preserved at: $smoke_failure_dir"
            log_info "Review $smoke_failure_dir/README.txt for debugging steps"
        fi
        
        return $smoke_exit_code
    fi
}

#######################################
# Cleanup and Error Handling
#######################################

cleanup_on_exit() {
    local exit_code=$?
    
    log_debug "Cleanup on exit (code: $exit_code)"
    
    # Kill any remaining background jobs
    if [[ ${#PROCESSING_PIDS[@]} -gt 0 ]]; then
        log_info "Terminating remaining background jobs..."
        for pid_info in "${PROCESSING_PIDS[@]}"; do
            IFS=':' read -r pid index <<< "$pid_info"
            if kill -0 "$pid" 2>/dev/null; then
                kill "$pid" 2>/dev/null || true
            fi
        done
    fi
    
    # Generate summary if we processed anything or have results
    if [[ $TOTAL_PROCESSED -gt 0 || ${#PROCESSING_RESULTS[@]} -gt 0 ]]; then
        aggregate_results
    fi
    
    # Cleanup temp base (optional, keep for debugging)
    # cleanup_safe "$TEMP_BASE"
    
    # Exit code propagation (Requirements 5.1, 5.2)
    # If we have failures, exit with non-zero code
    # Preserve original exit code if it was already non-zero
    if [[ $exit_code -ne 0 ]]; then
        exit $exit_code
    elif [[ $TOTAL_FAILED -gt 0 ]]; then
        exit 1
    else
        exit 0
    fi
}

handle_interrupt() {
    log_warn "Received interrupt signal. Cleaning up..."
    cleanup_on_exit
}

# Set up signal handlers
trap cleanup_on_exit EXIT
trap handle_interrupt SIGINT SIGTERM

#######################################
# Main Function
#######################################

main() {
    # Parse command-line arguments
    parse_arguments "$@"
    
    # Handle smoke test mode (Requirements: 10.1, 10.4)
    if [[ "$SMOKE_TEST" == true ]]; then
        log_info "Smoke test mode enabled"
        
        # Initialize minimal environment for smoke test
        mkdir -p "$OUTPUT_DIR"
        mkdir -p "$TEMP_BASE"
        
        # Run smoke test
        if run_smoke_test; then
            log_success "Smoke test completed successfully"
            exit 0
        else
            local smoke_exit_code=$?
            log_error "Smoke test failed"
            exit $smoke_exit_code
        fi
    fi
    
    # Initialize environment
    initialize_environment
    
    log_info "Starting ATX orchestration"
    log_info "CSV file: $CSV_FILE"
    log_info "Execution mode: $EXECUTION_MODE"
    log_info "Output directory: $OUTPUT_DIR"
    
    if [[ "$DRY_RUN" == true ]]; then
        log_info "DRY RUN MODE - No actual execution will occur"
    fi
    
    # Check prerequisites
    check_aws_cli
    
    if ! command -v atx &> /dev/null; then
        die "ATX CLI not found. Please install ATX CLI first." 2
    fi
    
    log_info "ATX CLI version: $(atx --version 2>&1 || echo 'unknown')"
    
    # Parse CSV file
    log_info "Parsing CSV file..."
    if ! parse_csv_file "$CSV_FILE"; then
        die "Failed to parse CSV file: $CSV_FILE" 1
    fi
    
    local queue_size=$(get_queue_size)
    log_info "Found $queue_size folders to process"
    
    if [[ $queue_size -eq 0 ]]; then
        die "No folders to process in CSV file" 1
    fi
    
    # Execute based on mode
    if [[ "$EXECUTION_MODE" == "serial" ]]; then
        execute_serial
    else
        execute_parallel
    fi
    
    # Results are aggregated in cleanup_on_exit
    log_success "Orchestration completed successfully!"
    
    # Exit code propagation (Requirements 5.1, 5.2)
    # Return 0 for all successful transformations, non-zero for any failures
    if [[ $TOTAL_FAILED -gt 0 ]]; then
        log_error "Orchestration completed with $TOTAL_FAILED failed transformation(s)"
        exit 1
    else
        exit 0
    fi
}

# Run main function
main "$@"
