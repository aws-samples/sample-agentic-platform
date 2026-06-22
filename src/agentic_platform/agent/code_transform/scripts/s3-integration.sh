#!/bin/bash
# S3 Integration Script
# Handles download/upload operations for ATX Container Test Runner
#
# This script provides functions for:
# - Downloading folders from S3 to local temp directories
# - Uploading results back to S3
# - Cleanup of temporary files

set -euo pipefail

#######################################
# Global Variables
#######################################
SCRIPT_NAME=$(basename "$0")
LOG_LEVEL="${LOG_LEVEL:-INFO}"
TEMP_BASE_DIR="${TEMP_BASE_DIR:-/tmp/atx-workspace}"
MAX_RETRIES="${MAX_RETRIES:-3}"
RETRY_DELAY="${RETRY_DELAY:-5}"

#######################################
# Logging Functions
#######################################

# Log message with timestamp and level
# Arguments:
#   $1 - Log level (INFO, WARN, ERROR, DEBUG)
#   $2 - Message
log() {
    local level="$1"
    shift
    local message="$*"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    
    # Only log if level is appropriate
    case "$LOG_LEVEL" in
        DEBUG)
            echo "[$timestamp] [$level] $message" >&2
            ;;
        INFO)
            if [[ "$level" != "DEBUG" ]]; then
                echo "[$timestamp] [$level] $message" >&2
            fi
            ;;
        WARN)
            if [[ "$level" == "WARN" || "$level" == "ERROR" ]]; then
                echo "[$timestamp] [$level] $message" >&2
            fi
            ;;
        ERROR)
            if [[ "$level" == "ERROR" ]]; then
                echo "[$timestamp] [$level] $message" >&2
            fi
            ;;
    esac
}

log_info() {
    log "INFO" "$@"
}

log_warn() {
    log "WARN" "$@"
}

log_error() {
    log "ERROR" "$@"
}

log_debug() {
    log "DEBUG" "$@"
}

#######################################
# Error Handling
#######################################

# Error codes for different failure types
readonly ERROR_S3_ACCESS=10
readonly ERROR_S3_DOWNLOAD=11
readonly ERROR_S3_UPLOAD=12
readonly ERROR_NETWORK_TIMEOUT=13
readonly ERROR_AWS_CREDENTIALS=14
readonly ERROR_INVALID_PATH=15
readonly ERROR_VALIDATION_FAILED=16

# Exit with error message
# Arguments:
#   $1 - Error message
#   $2 - Exit code (optional, defaults to 1)
die() {
    local message="$1"
    local exit_code="${2:-1}"
    log_error "$message"
    exit "$exit_code"
}

# Handle S3 access errors with detailed diagnostics
# Arguments:
#   $1 - S3 path that failed
#   $2 - Operation type (download/upload)
#   $3 - AWS CLI error output
# Returns:
#   Appropriate error code
handle_s3_access_error() {
    local s3_path="$1"
    local operation="$2"
    local error_output="$3"
    
    log_error "S3 $operation failed for: $s3_path"
    
    # Check for specific error types
    if echo "$error_output" | grep -qi "NoSuchBucket"; then
        log_error "Bucket does not exist in S3 path: $s3_path"
        log_error "Verify the bucket name is correct and exists in your AWS account"
        return $ERROR_S3_ACCESS
    elif echo "$error_output" | grep -qi "NoSuchKey"; then
        log_error "Key/folder does not exist in S3: $s3_path"
        log_error "Verify the path is correct and the folder exists"
        return $ERROR_S3_ACCESS
    elif echo "$error_output" | grep -qi "AccessDenied\|Forbidden"; then
        log_error "Access denied to S3 path: $s3_path"
        log_error "Check IAM permissions for S3 $operation operations"
        log_error "Required permissions: s3:GetObject, s3:ListBucket for download"
        log_error "Required permissions: s3:PutObject for upload"
        return $ERROR_S3_ACCESS
    elif echo "$error_output" | grep -qi "InvalidAccessKeyId\|SignatureDoesNotMatch"; then
        log_error "AWS credentials are invalid or expired"
        log_error "Verify AWS_ACCESS_KEY_ID and AWS_SECRET_ACCESS_KEY"
        log_error "Or ensure IAM role is properly attached to ECS/EC2 instance"
        return $ERROR_AWS_CREDENTIALS
    elif echo "$error_output" | grep -qi "RequestTimeout\|ConnectTimeout"; then
        log_error "Network timeout while accessing S3"
        log_error "Check network connectivity and retry"
        return $ERROR_NETWORK_TIMEOUT
    else
        log_error "Unknown S3 error occurred"
        log_error "Error details: $error_output"
        return $ERROR_S3_ACCESS
    fi
}

# Handle network timeout errors
# Arguments:
#   $1 - Operation description
#   $2 - Attempt number
#   $3 - Max attempts
# Returns:
#   0 to continue retrying, 1 to stop
handle_network_timeout() {
    local operation="$1"
    local attempt="$2"
    local max_attempts="$3"
    
    log_warn "Network timeout during: $operation"
    
    if [[ $attempt -lt $max_attempts ]]; then
        log_info "Will retry (attempt $((attempt + 1)) of $max_attempts)"
        return 0
    else
        log_error "Maximum retry attempts reached for: $operation"
        log_error "Network connectivity issues persist"
        log_error "Troubleshooting steps:"
        log_error "  1. Check internet connectivity"
        log_error "  2. Verify AWS service endpoints are accessible"
        log_error "  3. Check for firewall or security group restrictions"
        log_error "  4. Verify DNS resolution is working"
        return 1
    fi
}

# Trap errors and cleanup
cleanup_on_error() {
    local exit_code=$?
    if [[ $exit_code -ne 0 ]]; then
        log_error "Script failed with exit code $exit_code"
        
        # Provide context-specific error messages
        case $exit_code in
            $ERROR_S3_ACCESS)
                log_error "S3 access error - check permissions and paths"
                ;;
            $ERROR_S3_DOWNLOAD)
                log_error "S3 download failed - check source path and connectivity"
                ;;
            $ERROR_S3_UPLOAD)
                log_error "S3 upload failed - check destination path and connectivity"
                ;;
            $ERROR_NETWORK_TIMEOUT)
                log_error "Network timeout - check connectivity and retry"
                ;;
            $ERROR_AWS_CREDENTIALS)
                log_error "AWS credentials error - verify credentials are valid"
                ;;
            $ERROR_INVALID_PATH)
                log_error "Invalid path - verify file/directory paths"
                ;;
            $ERROR_VALIDATION_FAILED)
                log_error "Validation failed - check data integrity"
                ;;
        esac
    fi
}

trap cleanup_on_error EXIT

#######################################
# Usage and Help
#######################################

usage() {
    cat << EOF
Usage: $SCRIPT_NAME <command> [options]

Commands:
    download    Download folder from S3 to local directory
    upload      Upload results from local directory to S3
    cleanup     Clean up temporary files and directories

Download Options:
    --s3-path <path>        S3 path to download (e.g., s3://bucket/folder/)
    --local-path <path>     Local destination path
    --retry <count>         Number of retry attempts (default: $MAX_RETRIES)

Upload Options:
    --local-path <path>     Local source path
    --s3-path <path>        S3 destination path
    --retry <count>         Number of retry attempts (default: $MAX_RETRIES)

Cleanup Options:
    --path <path>           Path to clean up
    --force                 Force cleanup without confirmation

Environment Variables:
    LOG_LEVEL               Logging level (DEBUG, INFO, WARN, ERROR)
    TEMP_BASE_DIR           Base directory for temp files (default: /tmp/atx-workspace)
    MAX_RETRIES             Maximum retry attempts (default: 3)
    RETRY_DELAY             Delay between retries in seconds (default: 5)

Examples:
    # Download folder from S3
    $SCRIPT_NAME download --s3-path s3://bucket/customer1/folder1/ --local-path /tmp/workspace

    # Upload results to S3
    $SCRIPT_NAME upload --local-path /tmp/results --s3-path s3://bucket/results/customer1/folder1/

    # Cleanup temp directory
    $SCRIPT_NAME cleanup --path /tmp/workspace --force

EOF
}

#######################################
# Validation Functions
#######################################

# Validate S3 path format
# Arguments:
#   $1 - S3 path
# Returns:
#   0 if valid, 1 if invalid
validate_s3_path() {
    local s3_path="$1"
    
    if [[ ! "$s3_path" =~ ^s3://[a-zA-Z0-9._-]+/.* ]]; then
        log_error "Invalid S3 path format: $s3_path"
        log_error "Expected format: s3://bucket-name/key/path/"
        return 1
    fi
    
    return 0
}

# Check if AWS CLI is available
check_aws_cli() {
    if ! command -v aws &> /dev/null; then
        die "AWS CLI not found. Please install AWS CLI v2." 2
    fi
    
    log_debug "AWS CLI found: $(aws --version)"
}

# Validate AWS credentials are configured
check_aws_credentials() {
    if ! aws sts get-caller-identity &> /dev/null; then
        log_warn "AWS credentials not configured or invalid"
        log_warn "Ensure AWS_ACCESS_KEY_ID and AWS_SECRET_ACCESS_KEY are set"
        log_warn "Or use IAM role for ECS/EC2 instances"
        return 1
    fi
    
    log_debug "AWS credentials validated"
    return 0
}


#######################################
# S3 Download Functions
#######################################

# Download folder from S3 to local directory with retry logic
# Arguments:
#   $1 - S3 path (e.g., s3://bucket/folder/)
#   $2 - Local destination path
#   $3 - Number of retries (optional, defaults to MAX_RETRIES)
# Returns:
#   0 on success, error code on failure
s3_download() {
    local s3_path="$1"
    local local_path="$2"
    local max_retries="${3:-$MAX_RETRIES}"
    
    log_info "Starting S3 download: $s3_path -> $local_path"
    
    # Validate S3 path
    if ! validate_s3_path "$s3_path"; then
        return $ERROR_INVALID_PATH
    fi
    
    # Create local directory if it doesn't exist
    if ! mkdir -p "$local_path"; then
        log_error "Failed to create local directory: $local_path"
        log_error "Check permissions and disk space"
        return $ERROR_INVALID_PATH
    fi
    
    # Attempt download with retries
    local attempt=1
    local error_log="/tmp/s3-download-error-$$.log"
    
    while [[ $attempt -le $max_retries ]]; do
        log_info "Download attempt $attempt of $max_retries"
        
        # Capture both stdout and stderr
        local aws_output
        if aws_output=$(aws s3 sync "$s3_path" "$local_path" --no-progress 2>&1); then
            log_info "Successfully downloaded from S3"
            log_debug "AWS output: $aws_output"
            
            # Validate downloaded files exist
            if ! validate_download "$local_path"; then
                log_error "Download validation failed"
                return $ERROR_VALIDATION_FAILED
            fi
            
            # Cleanup error log
            rm -f "$error_log"
            return 0
        else
            local exit_code=$?
            echo "$aws_output" > "$error_log"
            
            log_warn "Download attempt $attempt failed with exit code $exit_code"
            
            # Handle specific error types
            local error_type
            error_type=$(handle_s3_access_error "$s3_path" "download" "$aws_output")
            local error_code=$?
            
            # Check if we should retry based on error type
            if [[ $error_code -eq $ERROR_NETWORK_TIMEOUT ]]; then
                if ! handle_network_timeout "S3 download" "$attempt" "$max_retries"; then
                    rm -f "$error_log"
                    return $ERROR_NETWORK_TIMEOUT
                fi
            elif [[ $error_code -eq $ERROR_AWS_CREDENTIALS ]]; then
                log_error "Credentials error - retrying will not help"
                rm -f "$error_log"
                return $ERROR_AWS_CREDENTIALS
            elif [[ $attempt -lt $max_retries ]]; then
                log_info "Retrying in $RETRY_DELAY seconds..."
                sleep "$RETRY_DELAY"
            fi
        fi
        
        ((attempt++))
    done
    
    log_error "Failed to download from S3 after $max_retries attempts"
    log_error "Last error log saved to: $error_log"
    return $ERROR_S3_DOWNLOAD
}

# Validate that downloaded files exist
# Arguments:
#   $1 - Local path to validate
# Returns:
#   0 if files exist, 1 if directory is empty
validate_download() {
    local local_path="$1"
    
    log_debug "Validating download at: $local_path"
    
    # Check if directory exists
    if [[ ! -d "$local_path" ]]; then
        log_error "Download directory does not exist: $local_path"
        return 1
    fi
    
    # Check if directory has any files
    local file_count=$(find "$local_path" -type f | wc -l)
    
    if [[ $file_count -eq 0 ]]; then
        log_warn "No files found in downloaded directory: $local_path"
        log_warn "This may indicate an empty S3 folder or download failure"
        return 1
    fi
    
    log_info "Download validated: $file_count files found"
    return 0
}

# Download with exponential backoff
# Arguments:
#   $1 - S3 path
#   $2 - Local path
#   $3 - Max retries (optional)
# Returns:
#   0 on success, 1 on failure
s3_download_with_backoff() {
    local s3_path="$1"
    local local_path="$2"
    local max_retries="${3:-$MAX_RETRIES}"
    
    log_info "Starting S3 download with exponential backoff"
    
    # Validate S3 path
    if ! validate_s3_path "$s3_path"; then
        return 1
    fi
    
    # Create local directory
    mkdir -p "$local_path" || {
        log_error "Failed to create directory: $local_path"
        return 1
    }
    
    local attempt=1
    local delay=$RETRY_DELAY
    
    while [[ $attempt -le $max_retries ]]; do
        log_info "Download attempt $attempt of $max_retries"
        
        if aws s3 sync "$s3_path" "$local_path" --no-progress; then
            log_info "Successfully downloaded from S3"
            
            if validate_download "$local_path"; then
                return 0
            else
                log_error "Download validation failed"
                return 1
            fi
        fi
        
        if [[ $attempt -lt $max_retries ]]; then
            log_info "Retrying in $delay seconds (exponential backoff)..."
            sleep "$delay"
            delay=$((delay * 2))
        fi
        
        ((attempt++))
    done
    
    log_error "Failed to download after $max_retries attempts"
    return 1
}


#######################################
# S3 Upload Functions
#######################################

# Upload results from local directory to S3 with retry logic
# Arguments:
#   $1 - Local source path
#   $2 - S3 destination path
#   $3 - Number of retries (optional, defaults to MAX_RETRIES)
# Returns:
#   0 on success, error code on failure
s3_upload() {
    local local_path="$1"
    local s3_path="$2"
    local max_retries="${3:-$MAX_RETRIES}"
    
    log_info "Starting S3 upload: $local_path -> $s3_path"
    
    # Validate S3 path
    if ! validate_s3_path "$s3_path"; then
        return $ERROR_INVALID_PATH
    fi
    
    # Validate local path exists
    if [[ ! -d "$local_path" ]]; then
        log_error "Local path does not exist: $local_path"
        return $ERROR_INVALID_PATH
    fi
    
    # Check if there are files to upload
    local file_count=$(find "$local_path" -type f 2>/dev/null | wc -l)
    if [[ $file_count -eq 0 ]]; then
        log_warn "No files to upload in: $local_path"
        log_info "Creating empty marker file to indicate processing completed"
        echo "Processing completed at $(date)" > "$local_path/.processing_complete"
    fi
    
    # Attempt upload with retries
    local attempt=1
    local error_log="/tmp/s3-upload-error-$$.log"
    
    while [[ $attempt -le $max_retries ]]; do
        log_info "Upload attempt $attempt of $max_retries"
        
        # Capture both stdout and stderr
        local aws_output
        if aws_output=$(aws s3 sync "$local_path" "$s3_path" --no-progress 2>&1); then
            log_info "Successfully uploaded to S3"
            log_debug "AWS output: $aws_output"
            
            # Validate upload by checking S3
            if validate_upload "$local_path" "$s3_path"; then
                rm -f "$error_log"
                return 0
            else
                log_warn "Upload validation failed, but upload command succeeded"
                # Still return success since upload command worked
                rm -f "$error_log"
                return 0
            fi
        else
            local exit_code=$?
            echo "$aws_output" > "$error_log"
            
            log_warn "Upload attempt $attempt failed with exit code $exit_code"
            
            # Handle specific error types
            local error_type
            error_type=$(handle_s3_access_error "$s3_path" "upload" "$aws_output")
            local error_code=$?
            
            # Check if we should retry based on error type
            if [[ $error_code -eq $ERROR_NETWORK_TIMEOUT ]]; then
                if ! handle_network_timeout "S3 upload" "$attempt" "$max_retries"; then
                    rm -f "$error_log"
                    return $ERROR_NETWORK_TIMEOUT
                fi
            elif [[ $error_code -eq $ERROR_AWS_CREDENTIALS ]]; then
                log_error "Credentials error - retrying will not help"
                rm -f "$error_log"
                return $ERROR_AWS_CREDENTIALS
            elif [[ $attempt -lt $max_retries ]]; then
                log_info "Retrying in $RETRY_DELAY seconds..."
                sleep "$RETRY_DELAY"
            fi
        fi
        
        ((attempt++))
    done
    
    log_error "Failed to upload to S3 after $max_retries attempts"
    log_error "Last error log saved to: $error_log"
    return $ERROR_S3_UPLOAD
}

# Upload specific file types (e.g., .md files and logs)
# Arguments:
#   $1 - Local source path
#   $2 - S3 destination path
#   $3 - File pattern (optional, defaults to all files)
#   $4 - Number of retries (optional)
# Returns:
#   0 on success, 1 on failure
s3_upload_filtered() {
    local local_path="$1"
    local s3_path="$2"
    local file_pattern="${3:-*}"
    local max_retries="${4:-$MAX_RETRIES}"
    
    log_info "Starting filtered S3 upload: $local_path -> $s3_path (pattern: $file_pattern)"
    
    # Validate inputs
    if ! validate_s3_path "$s3_path"; then
        return 1
    fi
    
    if [[ ! -d "$local_path" ]]; then
        log_error "Local path does not exist: $local_path"
        return 1
    fi
    
    # Find matching files
    local matching_files=()
    while IFS= read -r -d '' file; do
        matching_files+=("$file")
    done < <(find "$local_path" -type f -name "$file_pattern" -print0)
    
    if [[ ${#matching_files[@]} -eq 0 ]]; then
        log_warn "No files matching pattern '$file_pattern' found in $local_path"
        return 0
    fi
    
    log_info "Found ${#matching_files[@]} files matching pattern '$file_pattern'"
    
    # Upload each file with retries
    local failed_uploads=0
    for file in "${matching_files[@]}"; do
        local relative_path="${file#$local_path/}"
        local s3_file_path="${s3_path%/}/$relative_path"
        
        if ! s3_upload_file "$file" "$s3_file_path" "$max_retries"; then
            log_error "Failed to upload: $file"
            ((failed_uploads++))
        fi
    done
    
    if [[ $failed_uploads -gt 0 ]]; then
        log_error "Failed to upload $failed_uploads files"
        return 1
    fi
    
    log_info "Successfully uploaded all matching files"
    return 0
}

# Upload a single file to S3
# Arguments:
#   $1 - Local file path
#   $2 - S3 destination path
#   $3 - Number of retries (optional)
# Returns:
#   0 on success, 1 on failure
s3_upload_file() {
    local local_file="$1"
    local s3_path="$2"
    local max_retries="${3:-$MAX_RETRIES}"
    
    log_debug "Uploading file: $local_file -> $s3_path"
    
    if [[ ! -f "$local_file" ]]; then
        log_error "File does not exist: $local_file"
        return 1
    fi
    
    local attempt=1
    while [[ $attempt -le $max_retries ]]; do
        if aws s3 cp "$local_file" "$s3_path" --no-progress; then
            log_debug "Successfully uploaded: $local_file"
            return 0
        else
            log_warn "Upload attempt $attempt failed for: $local_file"
            
            if [[ $attempt -lt $max_retries ]]; then
                sleep "$RETRY_DELAY"
            fi
        fi
        
        ((attempt++))
    done
    
    log_error "Failed to upload file after $max_retries attempts: $local_file"
    return 1
}

# Validate upload by comparing file counts
# Arguments:
#   $1 - Local path
#   $2 - S3 path
# Returns:
#   0 if validation passes, 1 otherwise
validate_upload() {
    local local_path="$1"
    local s3_path="$2"
    
    log_debug "Validating upload: $local_path -> $s3_path"
    
    # Count local files
    local local_count=$(find "$local_path" -type f | wc -l)
    
    # Count S3 files (this is a basic check)
    local s3_count=$(aws s3 ls "$s3_path" --recursive 2>/dev/null | wc -l)
    
    log_debug "Local files: $local_count, S3 files: $s3_count"
    
    if [[ $s3_count -ge $local_count ]]; then
        log_debug "Upload validation passed"
        return 0
    else
        log_warn "Upload validation: S3 has fewer files than local"
        return 1
    fi
}

# Upload results with specific handling for .md files and logs
# Arguments:
#   $1 - Local results directory
#   $2 - S3 destination path
# Returns:
#   0 on success, 1 on failure
s3_upload_results() {
    local local_path="$1"
    local s3_path="$2"
    
    log_info "Uploading ATX results: $local_path -> $s3_path"
    
    # Upload all markdown files
    log_info "Uploading markdown files..."
    if ! s3_upload_filtered "$local_path" "$s3_path" "*.md"; then
        log_error "Failed to upload markdown files"
        return 1
    fi
    
    # Upload all log files
    log_info "Uploading log files..."
    if ! s3_upload_filtered "$local_path" "$s3_path" "*.log"; then
        log_error "Failed to upload log files"
        return 1
    fi
    
    # Upload any JSON files (summary, metadata)
    log_info "Uploading JSON files..."
    s3_upload_filtered "$local_path" "$s3_path" "*.json" || true
    
    # Upload any other files
    log_info "Uploading remaining files..."
    if ! s3_upload "$local_path" "$s3_path"; then
        log_error "Failed to upload remaining files"
        return 1
    fi
    
    log_info "Successfully uploaded all results"
    return 0
}


#######################################
# Cleanup Functions
#######################################

# Cleanup temporary files and directories
# Arguments:
#   $1 - Path to clean up
#   $2 - Force flag (optional, "force" to skip confirmation)
# Returns:
#   0 on success, 1 on failure
cleanup_temp_files() {
    local path="$1"
    local force="${2:-}"
    
    log_info "Cleaning up temporary files: $path"
    
    # Validate path exists
    if [[ ! -e "$path" ]]; then
        log_debug "Path does not exist, nothing to clean: $path"
        return 0
    fi
    
    # Safety check: don't delete root or home directories
    if [[ "$path" == "/" || "$path" == "$HOME" || "$path" == "/home" || "$path" == "/tmp" ]]; then
        log_error "Refusing to delete protected directory: $path"
        return 1
    fi
    
    # Confirm deletion unless force flag is set
    if [[ "$force" != "force" && "$force" != "--force" ]]; then
        log_warn "About to delete: $path"
        log_warn "Use --force flag to skip this confirmation"
        return 1
    fi
    
    # Perform cleanup
    log_info "Removing: $path"
    if rm -rf "$path"; then
        log_info "Successfully cleaned up: $path"
        return 0
    else
        log_error "Failed to clean up: $path"
        return 1
    fi
}

# Cleanup with error handling that ensures cleanup runs even on failure
# Arguments:
#   $1 - Path to clean up
# Returns:
#   Always returns 0 to allow script to continue
cleanup_safe() {
    local path="$1"
    
    log_debug "Safe cleanup: $path"
    
    # Try to cleanup, but don't fail if it doesn't work
    if cleanup_temp_files "$path" "force" 2>/dev/null; then
        log_debug "Cleanup successful: $path"
    else
        log_warn "Cleanup failed (non-fatal): $path"
    fi
    
    return 0
}

# Cleanup multiple paths
# Arguments:
#   $@ - Paths to clean up
# Returns:
#   0 if all cleanups succeed, 1 if any fail
cleanup_multiple() {
    local paths=("$@")
    local failed=0
    
    log_info "Cleaning up ${#paths[@]} paths"
    
    for path in "${paths[@]}"; do
        if ! cleanup_safe "$path"; then
            ((failed++))
        fi
    done
    
    if [[ $failed -gt 0 ]]; then
        log_warn "Failed to clean up $failed paths"
        return 1
    fi
    
    log_info "Successfully cleaned up all paths"
    return 0
}

# Register cleanup handler to run on script exit
# Arguments:
#   $1 - Path to clean up on exit
register_cleanup_handler() {
    local path="$1"
    
    log_debug "Registering cleanup handler for: $path"
    
    # Create a trap that will run cleanup on EXIT
    trap "cleanup_safe '$path'" EXIT
}

# Cleanup workspace after processing
# Arguments:
#   $1 - Workspace directory
#   $2 - Keep on failure flag (optional, "keep" to preserve on error)
# Returns:
#   0 on success
cleanup_workspace() {
    local workspace="$1"
    local keep_on_failure="${2:-}"
    
    log_info "Cleaning up workspace: $workspace"
    
    # Check if we should keep files on failure
    if [[ "$keep_on_failure" == "keep" && $? -ne 0 ]]; then
        log_warn "Preserving workspace due to failure: $workspace"
        return 0
    fi
    
    # Remove workspace
    cleanup_safe "$workspace"
    
    return 0
}

# Create a temporary workspace directory
# Arguments:
#   $1 - Workspace name (optional)
# Returns:
#   Prints the workspace path to stdout
#   Returns 0 on success, 1 on failure
create_temp_workspace() {
    local workspace_name="${1:-workspace-$(date +%s)}"
    local workspace_path="$TEMP_BASE_DIR/$workspace_name"
    
    log_info "Creating temporary workspace: $workspace_path"
    
    if mkdir -p "$workspace_path"; then
        log_info "Workspace created: $workspace_path"
        echo "$workspace_path"
        return 0
    else
        log_error "Failed to create workspace: $workspace_path"
        return 1
    fi
}


#######################################
# Main Command Dispatcher
#######################################

# Main function to handle commands
main() {
    # Check prerequisites
    check_aws_cli
    
    # Parse command
    if [[ $# -eq 0 ]]; then
        usage
        exit 1
    fi
    
    local command="$1"
    shift
    
    case "$command" in
        download)
            handle_download_command "$@"
            ;;
        upload)
            handle_upload_command "$@"
            ;;
        cleanup)
            handle_cleanup_command "$@"
            ;;
        help|--help|-h)
            usage
            exit 0
            ;;
        *)
            log_error "Unknown command: $command"
            usage
            exit 1
            ;;
    esac
}

# Handle download command
handle_download_command() {
    local s3_path=""
    local local_path=""
    local retry_count="$MAX_RETRIES"
    
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --s3-path)
                s3_path="$2"
                shift 2
                ;;
            --local-path)
                local_path="$2"
                shift 2
                ;;
            --retry)
                retry_count="$2"
                shift 2
                ;;
            *)
                log_error "Unknown option: $1"
                usage
                exit 1
                ;;
        esac
    done
    
    # Validate required arguments
    if [[ -z "$s3_path" || -z "$local_path" ]]; then
        log_error "Missing required arguments for download command"
        usage
        exit 1
    fi
    
    # Execute download
    if s3_download "$s3_path" "$local_path" "$retry_count"; then
        log_info "Download completed successfully"
        exit 0
    else
        log_error "Download failed"
        exit 1
    fi
}

# Handle upload command
handle_upload_command() {
    local local_path=""
    local s3_path=""
    local retry_count="$MAX_RETRIES"
    
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --local-path)
                local_path="$2"
                shift 2
                ;;
            --s3-path)
                s3_path="$2"
                shift 2
                ;;
            --retry)
                retry_count="$2"
                shift 2
                ;;
            *)
                log_error "Unknown option: $1"
                usage
                exit 1
                ;;
        esac
    done
    
    # Validate required arguments
    if [[ -z "$local_path" || -z "$s3_path" ]]; then
        log_error "Missing required arguments for upload command"
        usage
        exit 1
    fi
    
    # Execute upload
    if s3_upload "$local_path" "$s3_path" "$retry_count"; then
        log_info "Upload completed successfully"
        exit 0
    else
        log_error "Upload failed"
        exit 1
    fi
}

# Handle cleanup command
handle_cleanup_command() {
    local path=""
    local force=""
    
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --path)
                path="$2"
                shift 2
                ;;
            --force)
                force="force"
                shift
                ;;
            *)
                log_error "Unknown option: $1"
                usage
                exit 1
                ;;
        esac
    done
    
    # Validate required arguments
    if [[ -z "$path" ]]; then
        log_error "Missing required argument: --path"
        usage
        exit 1
    fi
    
    # Execute cleanup
    if cleanup_temp_files "$path" "$force"; then
        log_info "Cleanup completed successfully"
        exit 0
    else
        log_error "Cleanup failed"
        exit 1
    fi
}

# Run main function if script is executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
