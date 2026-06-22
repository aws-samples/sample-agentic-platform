#!/bin/bash
# CSV Parser for S3 Paths
# Parses CSV files with S3 paths and generates processing queue
#
# Requirements: 2.1, 2.2, 2.4, 2.5, 6.1, 8.2

set -euo pipefail

# Global arrays to store parsed data
declare -a S3_PATHS=()
declare -a BUILD_COMMANDS=()
declare -a TRANSFORMATION_NAMES=()
declare -a OUTPUT_S3_PATHS=()

# Parse a CSV line handling quoted fields and special characters
# Arguments:
#   $1 - CSV line to parse
# Returns:
#   Populates global array CSV_FIELDS with parsed values
parse_csv_line() {
    local line="$1"
    CSV_FIELDS=()
    
    # Handle empty lines
    if [[ -z "$line" || "$line" =~ ^[[:space:]]*$ ]]; then
        return 1
    fi
    
    local field=""
    local in_quotes=false
    local i=0
    
    while [ $i -lt ${#line} ]; do
        local char="${line:$i:1}"
        
        if [ "$char" = '"' ]; then
            if $in_quotes; then
                # Check for escaped quote (double quote)
                if [ $((i + 1)) -lt ${#line} ] && [ "${line:$((i + 1)):1}" = '"' ]; then
                    field="${field}\""
                    i=$((i + 1))
                else
                    in_quotes=false
                fi
            else
                in_quotes=true
            fi
        elif [ "$char" = ',' ] && ! $in_quotes; then
            CSV_FIELDS+=("$field")
            field=""
        else
            field="${field}${char}"
        fi
        
        i=$((i + 1))
    done
    
    # Add the last field
    CSV_FIELDS+=("$field")
    
    return 0
}

# Validate S3 URI format
# Arguments:
#   $1 - S3 URI to validate
# Returns:
#   0 if valid, 1 if invalid
validate_s3_uri() {
    local uri="$1"
    
    # Check if URI starts with s3://
    if [[ ! "$uri" =~ ^s3:// ]]; then
        return 1
    fi
    
    # Extract bucket and key
    local path="${uri#s3://}"
    
    # Check if bucket name exists (at least one character before /)
    if [[ ! "$path" =~ ^[^/]+/ ]]; then
        return 1
    fi
    
    return 0
}

# Parse CSV file and populate global arrays
# Arguments:
#   $1 - Path to CSV file
# Returns:
#   0 on success, 1 on error
parse_csv_file() {
    local csv_file="$1"
    local line_number=0
    local header_found=false
    
    # Check if file exists
    if [[ ! -f "$csv_file" ]]; then
        echo "ERROR: CSV file not found: $csv_file" >&2
        return 1
    fi
    
    # Read CSV file line by line
    while IFS= read -r line || [[ -n "$line" ]]; do
        line_number=$((line_number + 1))
        
        # Skip empty lines and comment lines
        if [[ -z "$line" || "$line" =~ ^[[:space:]]*$ || "$line" =~ ^[[:space:]]*# ]]; then
            continue
        fi
        
        # Parse the line
        if ! parse_csv_line "$line"; then
            continue
        fi
        
        # Check if this is the header row
        if ! $header_found; then
            # Validate header columns
            local expected_cols=("s3_path" "build_command" "transformation_name" "output_s3_path")
            local has_required_cols=true
            
            # Check we have at least 3 columns
            if [[ ${#CSV_FIELDS[@]} -lt 3 ]]; then
                echo "ERROR: Header must have at least 3 columns (s3_path, build_command, transformation_name) at line $line_number" >&2
                return 1
            fi
            
            # Check for required columns (first 3 are required)
            if [[ "${CSV_FIELDS[0]}" != "s3_path" ]]; then
                echo "ERROR: Missing required column 's3_path' in header at line $line_number" >&2
                return 1
            fi
            
            if [[ "${CSV_FIELDS[1]}" != "build_command" ]]; then
                echo "ERROR: Missing required column 'build_command' in header at line $line_number" >&2
                return 1
            fi
            
            if [[ "${CSV_FIELDS[2]}" != "transformation_name" ]]; then
                echo "ERROR: Missing required column 'transformation_name' in header at line $line_number" >&2
                return 1
            fi
            
            header_found=true
            continue
        fi
        
        # Validate we have at least 3 fields
        if [[ ${#CSV_FIELDS[@]} -lt 3 ]]; then
            echo "ERROR: Invalid CSV format at line $line_number: Expected at least 3 columns, got ${#CSV_FIELDS[@]}" >&2
            return 1
        fi
        
        local s3_path="${CSV_FIELDS[0]}"
        local build_command="${CSV_FIELDS[1]}"
        local transformation_name="${CSV_FIELDS[2]}"
        local output_s3_path=""
        
        # Fourth column is optional
        if [[ ${#CSV_FIELDS[@]} -ge 4 ]]; then
            output_s3_path="${CSV_FIELDS[3]}"
        fi
        
        # Validate S3 path
        if ! validate_s3_uri "$s3_path"; then
            echo "ERROR: Invalid S3 URI format at line $line_number: '$s3_path'" >&2
            echo "       Expected format: s3://bucket/key" >&2
            return 1
        fi
        
        # Validate output S3 path if provided
        if [[ -n "$output_s3_path" ]] && ! validate_s3_uri "$output_s3_path"; then
            echo "ERROR: Invalid output S3 URI format at line $line_number: '$output_s3_path'" >&2
            echo "       Expected format: s3://bucket/key" >&2
            return 1
        fi
        
        # Validate required fields are not empty
        if [[ -z "$s3_path" ]]; then
            echo "ERROR: Empty s3_path at line $line_number" >&2
            return 1
        fi
        
        if [[ -z "$build_command" ]]; then
            echo "ERROR: Empty build_command at line $line_number" >&2
            return 1
        fi
        
        if [[ -z "$transformation_name" ]]; then
            echo "ERROR: Empty transformation_name at line $line_number" >&2
            return 1
        fi
        
        # Add to arrays
        S3_PATHS+=("$s3_path")
        BUILD_COMMANDS+=("$build_command")
        TRANSFORMATION_NAMES+=("$transformation_name")
        OUTPUT_S3_PATHS+=("$output_s3_path")
        
    done < "$csv_file"
    
    # Check if we found a header
    if ! $header_found; then
        echo "ERROR: No valid header row found in CSV file" >&2
        return 1
    fi
    
    # Check if we have any data rows
    if [[ ${#S3_PATHS[@]} -eq 0 ]]; then
        echo "ERROR: No data rows found in CSV file" >&2
        return 1
    fi
    
    return 0
}

# Generate processing queue
# Arguments:
#   None (uses global arrays)
# Returns:
#   Prints processing queue to stdout
generate_processing_queue() {
    local count=${#S3_PATHS[@]}
    
    echo "Processing queue generated: $count items"
    echo ""
    
    for i in "${!S3_PATHS[@]}"; do
        echo "Item $((i + 1)):"
        echo "  S3 Path: ${S3_PATHS[$i]}"
        echo "  Build Command: ${BUILD_COMMANDS[$i]}"
        echo "  Transformation: ${TRANSFORMATION_NAMES[$i]}"
        if [[ -n "${OUTPUT_S3_PATHS[$i]}" ]]; then
            echo "  Output S3 Path: ${OUTPUT_S3_PATHS[$i]}"
        fi
        echo ""
    done
}

# Get the number of items in the processing queue
# Returns:
#   Number of items
get_queue_size() {
    echo "${#S3_PATHS[@]}"
}

# Get item from queue by index
# Arguments:
#   $1 - Index (0-based)
# Returns:
#   Prints item details in format: s3_path|build_command|transformation_name|output_s3_path
get_queue_item() {
    local index="$1"
    
    if [[ $index -lt 0 || $index -ge ${#S3_PATHS[@]} ]]; then
        echo "ERROR: Invalid queue index: $index" >&2
        return 1
    fi
    
    echo "${S3_PATHS[$index]}|${BUILD_COMMANDS[$index]}|${TRANSFORMATION_NAMES[$index]}|${OUTPUT_S3_PATHS[$index]}"
}

# Get all queue items as an array
# Returns:
#   Prints all items, one per line in format: s3_path|build_command|transformation_name|output_s3_path
get_all_queue_items() {
    for i in "${!S3_PATHS[@]}"; do
        echo "${S3_PATHS[$i]}|${BUILD_COMMANDS[$i]}|${TRANSFORMATION_NAMES[$i]}|${OUTPUT_S3_PATHS[$i]}"
    done
}

# Process queue in serial mode
# This function is a placeholder for the orchestrator to implement
# Arguments:
#   $1 - Processing function to call for each item
process_queue_serial() {
    local process_func="$1"
    
    for i in "${!S3_PATHS[@]}"; do
        local item="${S3_PATHS[$i]}|${BUILD_COMMANDS[$i]}|${TRANSFORMATION_NAMES[$i]}|${OUTPUT_S3_PATHS[$i]}"
        $process_func "$item" "$i"
    done
}

# Process queue in parallel mode
# This function is a placeholder for the orchestrator to implement
# Arguments:
#   $1 - Processing function to call for each item
#   $2 - Maximum parallel jobs (optional, default: 4)
process_queue_parallel() {
    local process_func="$1"
    local max_jobs="${2:-4}"
    
    echo "Parallel processing with max $max_jobs jobs"
    
    # This will be implemented by the orchestrator using background jobs
    # For now, just document the interface
    for i in "${!S3_PATHS[@]}"; do
        local item="${S3_PATHS[$i]}|${BUILD_COMMANDS[$i]}|${TRANSFORMATION_NAMES[$i]}|${OUTPUT_S3_PATHS[$i]}"
        echo "Would process in parallel: $item"
    done
}

# Main function for testing
main() {
    if [[ $# -lt 1 ]]; then
        echo "Usage: $0 <csv_file>" >&2
        exit 1
    fi
    
    local csv_file="$1"
    
    if ! parse_csv_file "$csv_file"; then
        exit 1
    fi
    
    generate_processing_queue
    
    echo "Total items in queue: $(get_queue_size)"
}

# Only run main if script is executed directly (not sourced)
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
