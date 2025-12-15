# Exit Codes and Output Modes

This document describes the exit code behavior and output modes implemented in the ATX Container Test Runner.

## Exit Code Propagation

The orchestrator script (`scripts/atx-orchestrator.sh`) implements proper exit code propagation to support CI/CD integration.

### Exit Code Behavior

| Exit Code | Meaning | Description |
|-----------|---------|-------------|
| 0 | Success | All transformations completed successfully |
| 1 | Failure | One or more transformations failed |
| 2+ | System Error | Missing dependencies, invalid configuration, etc. |

### Implementation Details

**Requirements Satisfied:**
- Requirement 5.1: Return 0 for all successful transformations
- Requirement 5.2: Return non-zero for any failures

**Key Implementation Points:**

1. **Main Function Exit**: The main function checks `TOTAL_FAILED` counter and exits with code 1 if any failures occurred, otherwise exits with 0.

2. **Cleanup Function**: The cleanup function preserves the original exit code if it was already non-zero, otherwise checks for failures and exits appropriately.

3. **Smoke Test**: The smoke test returns 0 on success, 1 on failure, allowing early detection of configuration issues.

### Usage in CI/CD

```bash
#!/bin/bash
# Example CI/CD integration

./scripts/atx-orchestrator.sh --csv-file repos.csv --quiet

if [ $? -eq 0 ]; then
    echo "All transformations passed"
    # Continue with deployment
else
    echo "Transformations failed"
    exit 1
fi
```

## Output Modes

The orchestrator supports three output modes to accommodate different use cases.

### Normal Mode (Default)

Balanced output suitable for interactive use:
- Info-level messages
- Success/failure notifications
- Summary statistics
- Progress indicators

**Usage:**
```bash
./scripts/atx-orchestrator.sh --csv-file repos.csv
```

### Verbose Mode

Detailed output for debugging and troubleshooting:
- All log messages (DEBUG, INFO, WARN, ERROR)
- Progress messages for each step
- Detailed timing information
- Full command output

**Requirements Satisfied:**
- Requirement 5.3: Output real-time progress to stdout when invoked with verbose flag

**Usage:**
```bash
./scripts/atx-orchestrator.sh --csv-file repos.csv --verbose
```

**When to Use:**
- Debugging transformation failures
- Understanding execution flow
- Troubleshooting performance issues
- Development and testing

### Quiet Mode

Minimal output for automated environments:
- Only ERROR-level messages displayed
- Suppresses info and success messages
- Full logs still written to files
- Suitable for CI/CD pipelines

**Requirements Satisfied:**
- Requirement 5.4: Suppress non-essential output when invoked with quiet flag

**Usage:**
```bash
./scripts/atx-orchestrator.sh --csv-file repos.csv --quiet
```

**When to Use:**
- CI/CD pipelines
- Automated batch processing
- Cron jobs
- When you only care about failures

## Implementation Architecture

### Logging Functions

The logging system is implemented across two scripts:

**s3-integration.sh:**
- `log()`: Base logging function with level filtering
- `log_info()`: Info-level messages
- `log_warn()`: Warning messages
- `log_error()`: Error messages
- `log_debug()`: Debug messages

**atx-orchestrator.sh:**
- `log_info()`: Respects QUIET flag
- `log_success()`: Respects QUIET flag
- `log_progress()`: Only outputs when VERBOSE=true and QUIET=false

### Flag Interaction

| Flag | VERBOSE | QUIET | LOG_LEVEL | Output Behavior |
|------|---------|-------|-----------|-----------------|
| (none) | false | false | INFO | Normal output |
| --verbose | true | false | DEBUG | All messages + progress |
| --quiet | false | true | ERROR | Only errors |
| --verbose --quiet | true | true | ERROR | Quiet takes precedence |

### Environment Variables

The output mode can also be controlled via environment variables:

```bash
# Set log level directly
LOG_LEVEL=DEBUG ./scripts/atx-orchestrator.sh --csv-file repos.csv

# Combine with flags
LOG_LEVEL=WARN ./scripts/atx-orchestrator.sh --csv-file repos.csv --verbose
```

## Testing

Exit code behavior is tested in `tests/test_exit_codes.sh`:

```bash
# Run exit code tests
./tests/test_exit_codes.sh
```

**Test Coverage:**
- Help flag returns 0
- Missing CSV file returns non-zero
- Invalid CSV file returns non-zero
- Verbose flag is accepted
- Quiet flag is accepted
- Smoke test flag is accepted

## Examples

### Example 1: CI/CD Pipeline

```bash
#!/bin/bash
# Jenkins/GitLab CI pipeline

set -e

# Run transformations in quiet mode
./scripts/atx-orchestrator.sh \
    --csv-file repos.csv \
    --mode parallel \
    --max-jobs 8 \
    --quiet

# Exit code automatically propagates
# Pipeline fails if any transformation fails
```

### Example 2: Interactive Debugging

```bash
# Run with verbose output to debug issues
./scripts/atx-orchestrator.sh \
    --csv-file repos.csv \
    --verbose \
    --output-dir ./debug_results

# Review detailed logs
cat ./debug_results/summary.log
```

### Example 3: Automated Monitoring

```bash
#!/bin/bash
# Cron job for automated processing

# Run in quiet mode, only log errors
./scripts/atx-orchestrator.sh \
    --csv-file /data/repos.csv \
    --quiet \
    --output-dir /var/log/atx/$(date +%Y%m%d)

# Send alert if failed
if [ $? -ne 0 ]; then
    echo "ATX transformations failed" | mail -s "Alert" admin@example.com
fi
```

## Best Practices

1. **Use Quiet Mode in CI/CD**: Reduces log noise while preserving full logs in files
2. **Use Verbose Mode for Debugging**: Provides detailed information for troubleshooting
3. **Check Exit Codes**: Always check exit codes in scripts and pipelines
4. **Review Log Files**: Even in quiet mode, full logs are written to files
5. **Combine with Dry Run**: Use `--dry-run --verbose` to preview execution without running

## Related Documentation

- [README.md](../README.md) - Main project documentation
- [scripts/README.md](../scripts/README.md) - Script documentation
- [examples/ci-cd-integration.sh](../examples/ci-cd-integration.sh) - CI/CD integration example
- [docs/troubleshooting.md](troubleshooting.md) - Troubleshooting guide

