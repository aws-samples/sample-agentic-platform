# Troubleshooting Guide

This guide provides solutions to common issues encountered when using the ATX Container Test Runner.

## Quick Diagnostics

Before diving into specific issues, run these quick checks:

```bash
# 1. Verify Docker is running
docker ps

# 2. Run smoke test
docker run --rm atx-test-runner:latest --smoke-test

# 3. Check AWS credentials
aws sts get-caller-identity

# 4. Verify S3 bucket access
aws s3 ls s3://your-source-bucket/

# 5. Check ECR authentication
aws ecr describe-repositories --region us-east-1
```

## Build Issues

### Docker Build Fails

**Symptom:** Docker build command fails with errors

**Common Error Messages:**
```
ERROR [internal] load metadata for docker.io/library/ubuntu:22.04
failed to solve with frontend dockerfile.v0
```

**Possible Causes:**
1. Docker daemon not running
2. Network connectivity issues
3. Insufficient disk space
4. Invalid Dockerfile syntax

**Solutions:**

```bash
# Check Docker is running
docker ps
# If error: "Cannot connect to the Docker daemon"
sudo systemctl start docker  # Linux
# or restart Docker Desktop on Mac/Windows

# Check disk space (need at least 2GB free)
df -h
docker system df  # Check Docker disk usage
docker system prune -a  # Clean up if needed

# Test network connectivity
curl -I https://hub.docker.com

# Verify Dockerfile syntax
docker build --no-cache -t atx-test-runner:latest .

# Build with verbose output
docker build --progress=plain -t atx-test-runner:latest .
```

### ATX Installation Fails

**Symptom:** ATX CLI installation fails during image build

**Common Error Messages:**
```
curl: (6) Could not resolve host: atx-install-url.com
curl: (7) Failed to connect to atx-install-url.com
```

**Possible Causes:**
1. Network connectivity issues
2. Proxy configuration needed
3. ATX installation URL changed
4. DNS resolution problems

**Solutions:**

```bash
# Test ATX installation URL
curl -I https://atx-install-url.com/install.sh

# Build with proxy settings
docker build \
  --build-arg HTTP_PROXY=http://proxy.example.com:8080 \
  --build-arg HTTPS_PROXY=http://proxy.example.com:8080 \
  -t atx-test-runner:latest .

# Check DNS resolution
nslookup atx-install-url.com

# Try building with host network (Linux only)
docker build --network=host -t atx-test-runner:latest .
```

### AWS CLI Installation Fails

**Symptom:** AWS CLI installation fails during image build

**Common Error Messages:**
```
curl: (28) Operation timed out after 300000 milliseconds
unzip: cannot find or open awscliv2.zip
```

**Solutions:**

```bash
# Increase Docker build timeout
export DOCKER_BUILDKIT=1
docker build --network=host -t atx-test-runner:latest .

# Manually download and verify AWS CLI installer
curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip"
unzip -t awscliv2.zip  # Test archive integrity

# Use alternative AWS CLI installation method in Dockerfile
# Add to Dockerfile:
# RUN pip3 install awscli --upgrade
```

## Runtime Issues

### S3 Access Denied

**Symptom:** Container fails with S3 permission errors

**Common Error Messages:**
```
An error occurred (AccessDenied) when calling the GetObject operation
fatal error: Unable to locate credentials
```

**Possible Causes:**
1. Missing or incorrect IAM permissions
2. AWS credentials not configured
3. Bucket policy denies access
4. Wrong bucket name or region

**Solutions:**

```bash
# Verify AWS credentials are configured
aws sts get-caller-identity

# Test S3 access manually
aws s3 ls s3://your-source-bucket/
aws s3 cp s3://your-source-bucket/test.txt ./

# Check IAM role permissions (if using IAM role)
aws iam get-role --role-name ATXRunnerTaskRole
aws iam list-attached-role-policies --role-name ATXRunnerTaskRole

# Verify bucket policy
aws s3api get-bucket-policy --bucket your-source-bucket

# Test with explicit credentials
docker run --rm \
  -e AWS_ACCESS_KEY_ID=your-key \
  -e AWS_SECRET_ACCESS_KEY=your-secret \
  -e AWS_REGION=us-east-1 \
  atx-test-runner:latest --smoke-test

# Check bucket region matches
aws s3api get-bucket-location --bucket your-source-bucket
```

**Required IAM Permissions:**

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "s3:GetObject",
        "s3:ListBucket"
      ],
      "Resource": [
        "arn:aws:s3:::source-bucket/*",
        "arn:aws:s3:::source-bucket"
      ]
    },
    {
      "Effect": "Allow",
      "Action": [
        "s3:PutObject",
        "s3:PutObjectAcl"
      ],
      "Resource": [
        "arn:aws:s3:::results-bucket/*"
      ]
    }
  ]
}
```

### Container Fails to Start

**Symptom:** Docker run command fails immediately

**Common Error Messages:**
```
docker: Error response from daemon: OCI runtime create failed
docker: invalid reference format
```

**Possible Causes:**
1. Invalid command syntax
2. Missing environment variables
3. Volume mount path doesn't exist
4. Image not found

**Solutions:**

```bash
# Check if image exists
docker images | grep atx-test-runner

# Verify container logs
docker ps -a  # List all containers including stopped
docker logs <container-id>

# Test with minimal command
docker run --rm atx-test-runner:latest --help

# Check volume mount paths exist
ls -la /path/to/mount

# Run with interactive shell for debugging
docker run -it --entrypoint /bin/bash atx-test-runner:latest

# Inside container, verify:
which atx
which aws
ls -la /usr/local/bin/
```

### ATX Transformation Fails

**Symptom:** ATX execution returns non-zero exit code

**Common Error Messages:**
```
ATX transformation failed with exit code: 1
Error: Transformation 'XYZ' not found
Error: Invalid code repository structure
```

**Possible Causes:**
1. Invalid transformation name
2. Code repository structure issues
3. Missing Progress code files
4. ATX authentication expired
5. Network connectivity issues

**Solutions:**

```bash
# Check transformation name is correct
# Common transformations:
# - Comprehensive-Codebase-Analysis
# - Code-Modernization
# - Security-Analysis

# Verify code structure in S3
aws s3 ls s3://source-bucket/customer1/folder1/ --recursive

# Check for .p files (Progress code)
aws s3 ls s3://source-bucket/customer1/folder1/ --recursive | grep "\.p$"

# Test ATX manually
docker run -it --entrypoint /bin/bash atx-test-runner:latest
# Inside container:
atx --version
atx custom def exec --help

# Check ATX authentication
atx auth status

# Review execution logs
cat orchestrator_results/customer1_folder1_execution.log

# Enable verbose mode for detailed output
docker run --rm \
  -e AWS_ACCESS_KEY_ID \
  -e AWS_SECRET_ACCESS_KEY \
  -v $(pwd)/repos.csv:/workspace/repos.csv \
  atx-test-runner:latest \
  --csv-file /workspace/repos.csv \
  --verbose
```

### CSV Parsing Errors

**Symptom:** Container fails with CSV parsing errors

**Common Error Messages:**
```
ERROR: Invalid CSV format at line 3
ERROR: Missing required column: s3_path
ERROR: Invalid S3 URI format
```

**Possible Causes:**
1. Incorrect CSV format
2. Missing header row
3. Special characters not quoted
4. Invalid S3 URI format

**Solutions:**

```bash
# Verify CSV format
cat repos.csv

# Check for required columns
head -1 repos.csv
# Expected: s3_path,build_command,transformation_name,output_s3_path

# Validate S3 URIs
grep -E "^s3://[a-z0-9.-]+/.*" repos.csv

# Check for special characters
cat -A repos.csv  # Shows hidden characters

# Test with sample CSV
cat > test.csv <<EOF
s3_path,build_command,transformation_name,output_s3_path
s3://source-bucket/test/,noop,Comprehensive-Codebase-Analysis,s3://results-bucket/test/
EOF

docker run --rm \
  -v $(pwd)/test.csv:/workspace/test.csv \
  atx-test-runner:latest \
  --csv-file /workspace/test.csv \
  --dry-run
```

## Performance Issues

### Slow S3 Downloads

**Symptom:** Downloads from S3 take excessive time

**Solutions:**
- Check network bandwidth
- Verify S3 bucket is in the same region as the container
- Consider using S3 Transfer Acceleration
- Check for throttling in CloudWatch metrics

### High Memory Usage

**Symptom:** Container runs out of memory

**Solutions:**
- Increase container memory limits
- Process fewer folders in parallel
- Check for memory leaks in transformation code

## Log File Locations

Understanding where logs are stored is crucial for troubleshooting.

### Local Execution Logs

When running the container locally, logs are stored in the output directory:

```
orchestrator_results/
├── summary.log              # Human-readable execution summary
├── results.json             # Machine-readable results
├── customer1_folder1_execution.log    # Per-folder execution logs
├── customer1_folder2_execution.log
├── customer2_menu1_execution.log
└── smoke_test_failure/      # Preserved on smoke test failure
    ├── workspace/
    │   └── test.p
    ├── smoke_test.log
    └── README.txt
```

**Key Log Files:**

| File | Description | When Created |
|------|-------------|--------------|
| `summary.log` | Overall execution summary with statistics | Always |
| `results.json` | Machine-readable results in JSON format | Always |
| `*_execution.log` | Individual folder execution logs | Per folder processed |
| `smoke_test.log` | Smoke test execution details | When `--smoke-test` used |
| `smoke_test_failure/` | Preserved artifacts on smoke test failure | On smoke test failure |

### ECS Logs

When running on ECS, logs are sent to CloudWatch Logs:

```bash
# View logs in CloudWatch
aws logs tail /ecs/atx-container-test-runner --follow

# Get log streams
aws logs describe-log-streams \
  --log-group-name /ecs/atx-container-test-runner \
  --order-by LastEventTime \
  --descending

# Get specific log stream
aws logs get-log-events \
  --log-group-name /ecs/atx-container-test-runner \
  --log-stream-name ecs/atx-container/<task-id>

# Filter logs by pattern
aws logs filter-log-events \
  --log-group-name /ecs/atx-container-test-runner \
  --filter-pattern "ERROR"

# Export logs to S3
aws logs create-export-task \
  --log-group-name /ecs/atx-container-test-runner \
  --from $(date -d '1 hour ago' +%s)000 \
  --to $(date +%s)000 \
  --destination s3://my-logs-bucket/ecs-logs/
```

### Kubernetes Logs

When running on EKS, logs are available via kubectl:

```bash
# View pod logs
kubectl logs job/atx-container-test-runner

# Follow logs in real-time
kubectl logs -f job/atx-container-test-runner

# View logs from specific container
kubectl logs job/atx-container-test-runner -c atx-runner

# View previous pod logs (if pod restarted)
kubectl logs job/atx-container-test-runner --previous

# Get logs from all pods in job
kubectl logs -l job-name=atx-container-test-runner

# Save logs to file
kubectl logs job/atx-container-test-runner > atx-logs.txt
```

### EC2 Logs

When running on EC2, logs are stored locally on the instance:

```bash
# Connect to instance
aws ssm start-session --target <instance-id>

# View setup logs
sudo tail -f /var/log/atx-runner-setup.log

# View Docker logs
sudo docker ps -a
sudo docker logs <container-id>

# View system logs
sudo journalctl -u docker -f

# Copy logs to S3 for analysis
aws s3 cp /var/log/atx-runner-setup.log s3://my-logs-bucket/ec2-logs/
```

## Debugging Tips

### Enable Verbose Mode

Verbose mode provides detailed output for troubleshooting:

```bash
# Local execution
docker run --rm \
  -e AWS_ACCESS_KEY_ID \
  -e AWS_SECRET_ACCESS_KEY \
  -v $(pwd)/repos.csv:/workspace/repos.csv \
  atx-test-runner:latest \
  --csv-file /workspace/repos.csv \
  --verbose

# ECS task override
aws ecs run-task \
  --cluster atx-runner-cluster \
  --task-definition atx-runner-task \
  --overrides '{
    "containerOverrides": [{
      "name": "atx-container",
      "command": ["--csv-file", "/workspace/repos.csv", "--verbose"]
    }]
  }'
```

### Use Dry Run Mode

Preview what will be executed without actually running:

```bash
docker run --rm \
  -v $(pwd)/repos.csv:/workspace/repos.csv \
  atx-test-runner:latest \
  --csv-file /workspace/repos.csv \
  --dry-run \
  --verbose
```

### Interactive Debugging

Access container shell for manual testing:

```bash
# Start container with shell
docker run -it --entrypoint /bin/bash atx-test-runner:latest

# Inside container, test components:
atx --version
aws --version
which atx
which aws
echo $PATH

# Test S3 access
aws s3 ls s3://source-bucket/

# Test ATX manually
cd /tmp
mkdir test-workspace
cd test-workspace
echo "/* test */" > test.p
atx custom def exec \
  --code-repository-path . \
  --transformation-name "Comprehensive-Codebase-Analysis" \
  --build-command "noop"
```

### Preserve Failed State

When failures occur, preserve the container state for inspection:

```bash
# List all containers (including stopped)
docker ps -a

# Find the failed container
docker ps -a | grep atx-test-runner

# Start the stopped container
docker start <container-id>

# Access shell in the container
docker exec -it <container-id> /bin/bash

# Inside container, inspect:
ls -la /tmp/
cat /workspace/results/summary.log
cat /workspace/results/*_execution.log
```

### Check Resource Usage

Monitor resource consumption to identify bottlenecks:

```bash
# Monitor Docker resource usage
docker stats

# Check specific container
docker stats <container-id>

# View container resource limits
docker inspect <container-id> | grep -A 10 "Memory"

# ECS task resource usage
aws ecs describe-tasks \
  --cluster atx-runner-cluster \
  --tasks <task-arn> \
  --query 'tasks[0].containers[0].{CPU:cpu,Memory:memory}'

# Kubernetes pod resource usage
kubectl top pod <pod-name>
```

### Network Debugging

Test network connectivity from within the container:

```bash
# Access container shell
docker run -it --entrypoint /bin/bash atx-test-runner:latest

# Test DNS resolution
nslookup s3.amazonaws.com
nslookup atx-service.amazon.com

# Test connectivity
curl -I https://s3.amazonaws.com
curl -I https://atx-service.amazon.com

# Test S3 endpoint
aws s3 ls --debug 2>&1 | grep -i endpoint

# Check network routes
ip route
netstat -rn
```

### Trace Script Execution

Enable bash tracing for detailed script execution:

```bash
# Run with bash tracing
docker run --rm \
  -e AWS_ACCESS_KEY_ID \
  -e AWS_SECRET_ACCESS_KEY \
  -v $(pwd)/repos.csv:/workspace/repos.csv \
  atx-test-runner:latest \
  bash -x /usr/local/bin/atx-orchestrator.sh \
  --csv-file /workspace/repos.csv

# Or set in environment
docker run --rm \
  -e AWS_ACCESS_KEY_ID \
  -e AWS_SECRET_ACCESS_KEY \
  -e BASH_XTRACEFD=1 \
  -v $(pwd)/repos.csv:/workspace/repos.csv \
  atx-test-runner:latest \
  --csv-file /workspace/repos.csv
```

## Common Error Messages and Solutions

### "AWS CLI not found"

**Error Message:**
```
/usr/local/bin/atx-orchestrator.sh: line 45: aws: command not found
ERROR: AWS CLI not found in PATH
```

**Cause:** AWS CLI not properly installed in container

**Solutions:**
```bash
# Verify AWS CLI in image
docker run --rm atx-test-runner:latest which aws
docker run --rm atx-test-runner:latest aws --version

# Rebuild image with verbose output
docker build --progress=plain -t atx-test-runner:latest .

# Check Dockerfile AWS CLI installation step
grep -A 10 "Install AWS CLI" Dockerfile
```

### "ATX command not found"

**Error Message:**
```
/usr/local/bin/atx-orchestrator.sh: line 67: atx: command not found
ERROR: ATX CLI not found in PATH
SMOKE TEST FAILED: ATX CLI not available
```

**Cause:** ATX CLI not in PATH or not installed

**Solutions:**
```bash
# Verify ATX in image
docker run --rm atx-test-runner:latest which atx
docker run --rm atx-test-runner:latest atx --version

# Check PATH
docker run --rm atx-test-runner:latest echo $PATH

# Verify ATX installation in Dockerfile
grep -A 10 "Install ATX" Dockerfile

# Run smoke test to verify
docker run --rm atx-test-runner:latest --smoke-test
```

### "CSV parsing error"

**Error Message:**
```
ERROR: Invalid CSV format at line 3: unexpected end of line
ERROR: Missing required column: s3_path
ERROR: Invalid S3 URI format: source-bucket/folder1/
```

**Cause:** Invalid CSV format

**Solutions:**
```bash
# Verify CSV structure
head -5 repos.csv

# Check for required columns
head -1 repos.csv | tr ',' '\n'

# Validate S3 URIs (must start with s3://)
grep -v "^s3://" repos.csv | grep -v "^s3_path"

# Check for hidden characters
cat -A repos.csv | head -5

# Test with minimal CSV
cat > test.csv <<EOF
s3_path,build_command,transformation_name,output_s3_path
s3://test-bucket/test/,noop,Comprehensive-Codebase-Analysis,s3://results/test/
EOF

docker run --rm \
  -v $(pwd)/test.csv:/workspace/test.csv \
  atx-test-runner:latest \
  --csv-file /workspace/test.csv \
  --dry-run
```

### "Permission denied" Errors

**Error Message:**
```
mkdir: cannot create directory '/tmp/workspace': Permission denied
touch: cannot touch '/workspace/results/summary.log': Permission denied
```

**Cause:** Insufficient permissions in container or on mounted volumes

**Solutions:**
```bash
# Check volume mount permissions
ls -la /path/to/mount

# Run container with user ID
docker run --rm \
  --user $(id -u):$(id -g) \
  -v $(pwd)/repos.csv:/workspace/repos.csv \
  atx-test-runner:latest \
  --csv-file /workspace/repos.csv

# Fix permissions on host
chmod 755 /path/to/mount
chown $(id -u):$(id -g) /path/to/mount

# Check container user
docker run --rm atx-test-runner:latest whoami
docker run --rm atx-test-runner:latest id
```

### "No space left on device"

**Error Message:**
```
Error response from daemon: no space left on device
write /tmp/workspace/file.p: no space left on device
```

**Cause:** Insufficient disk space

**Solutions:**
```bash
# Check disk space
df -h
docker system df

# Clean up Docker resources
docker system prune -a
docker volume prune
docker image prune -a

# Remove old containers
docker container prune

# Check specific directory space
du -sh /var/lib/docker
du -sh /tmp
```

### "Task failed to start" (ECS)

**Error Message:**
```
ResourceInitializationError: unable to pull secrets or registry auth
CannotPullContainerError: Error response from daemon
```

**Cause:** ECR authentication or network issues

**Solutions:**
```bash
# Verify task execution role has ECR permissions
aws iam get-role-policy \
  --role-name ecsTaskExecutionRole \
  --policy-name ECRAccessPolicy

# Check ECR repository exists
aws ecr describe-repositories \
  --repository-names atx-test-runner

# Verify image exists in ECR
aws ecr describe-images \
  --repository-name atx-test-runner \
  --image-ids imageTag=latest

# Check VPC/subnet configuration
# Ensure subnets have NAT gateway for internet access
aws ec2 describe-subnets --subnet-ids subnet-xxxxx

# Test ECR pull manually
aws ecr get-login-password | docker login --username AWS --password-stdin <ecr-uri>
docker pull <ecr-uri>:latest
```

### "Transformation timeout"

**Error Message:**
```
ERROR: ATX transformation timed out after 3600 seconds
ERROR: Transformation did not complete within expected time
```

**Cause:** Large codebase or slow transformation

**Solutions:**
```bash
# Increase task timeout (ECS)
# Update task definition with longer timeout

# Use parallel mode for multiple folders
docker run --rm \
  -v $(pwd)/repos.csv:/workspace/repos.csv \
  atx-test-runner:latest \
  --csv-file /workspace/repos.csv \
  --mode parallel \
  --max-jobs 4

# Process folders in smaller batches
# Split CSV into multiple files

# Check transformation progress
docker logs -f <container-id>
```

## Troubleshooting Workflow

Follow this systematic approach to diagnose and resolve issues:

### Step 1: Identify the Problem

```bash
# Run smoke test first
docker run --rm atx-test-runner:latest --smoke-test

# If smoke test passes, test with minimal CSV
cat > minimal.csv <<EOF
s3_path,build_command,transformation_name,output_s3_path
s3://source-bucket/test/,noop,Comprehensive-Codebase-Analysis,s3://results/test/
EOF

docker run --rm \
  -e AWS_ACCESS_KEY_ID \
  -e AWS_SECRET_ACCESS_KEY \
  -v $(pwd)/minimal.csv:/workspace/minimal.csv \
  atx-test-runner:latest \
  --csv-file /workspace/minimal.csv \
  --verbose
```

### Step 2: Check Prerequisites

```bash
# Verify Docker
docker --version
docker ps

# Verify AWS credentials
aws sts get-caller-identity

# Verify S3 access
aws s3 ls s3://source-bucket/
aws s3 ls s3://results-bucket/

# Verify ECR access (if using ECR)
aws ecr describe-repositories
```

### Step 3: Review Logs

```bash
# Local execution
cat orchestrator_results/summary.log
cat orchestrator_results/*_execution.log

# ECS execution
aws logs tail /ecs/atx-container-test-runner --follow

# Kubernetes execution
kubectl logs job/atx-container-test-runner

# EC2 execution
aws ssm start-session --target <instance-id>
sudo tail -f /var/log/atx-runner-setup.log
```

### Step 4: Test Components Individually

```bash
# Test S3 download
aws s3 sync s3://source-bucket/customer1/folder1/ /tmp/test-download/

# Test ATX manually
docker run -it --entrypoint /bin/bash atx-test-runner:latest
# Inside container:
cd /tmp
mkdir test && cd test
echo "/* test */" > test.p
atx custom def exec \
  --code-repository-path . \
  --transformation-name "Comprehensive-Codebase-Analysis" \
  --build-command "noop"
```

### Step 5: Isolate the Issue

```bash
# Test with single folder
# Create CSV with one entry
cat > single.csv <<EOF
s3_path,build_command,transformation_name,output_s3_path
s3://source-bucket/customer1/folder1/,noop,Comprehensive-Codebase-Analysis,s3://results/customer1/folder1/
EOF

# Run with verbose output
docker run --rm \
  -e AWS_ACCESS_KEY_ID \
  -e AWS_SECRET_ACCESS_KEY \
  -v $(pwd)/single.csv:/workspace/single.csv \
  -v $(pwd)/results:/workspace/results \
  atx-test-runner:latest \
  --csv-file /workspace/single.csv \
  --output-dir /workspace/results \
  --verbose

# Review results
cat results/summary.log
cat results/*_execution.log
```

### Step 6: Escalate if Needed

If the issue persists after following these steps:

1. **Gather Information:**
   ```bash
   # Collect logs
   tar -czf atx-debug-logs.tar.gz orchestrator_results/
   
   # Collect configuration
   cp repos.csv atx-debug-config.csv
   
   # Collect environment info
   docker version > atx-debug-env.txt
   aws --version >> atx-debug-env.txt
   uname -a >> atx-debug-env.txt
   ```

2. **Document the Issue:**
   - Error messages (exact text)
   - Steps to reproduce
   - Expected vs actual behavior
   - Environment details (OS, Docker version, AWS region)
   - Logs and configuration files

3. **Check Documentation:**
   - [README.md](../README.md) - Main documentation
   - [Deployment Guide](deployment.md) - Deployment instructions
   - [Exit Codes and Output Modes](exit-codes-and-output-modes.md) - Exit code reference
   - [Smoke Test Documentation](smoke-test.md) - Smoke test details

## Performance Troubleshooting

### Slow Execution

**Symptoms:**
- Transformations take longer than expected
- High CPU or memory usage
- Timeouts

**Diagnostic Steps:**

```bash
# Monitor resource usage
docker stats

# Check parallel execution
# Increase max-jobs if resources available
docker run --rm \
  -v $(pwd)/repos.csv:/workspace/repos.csv \
  atx-test-runner:latest \
  --csv-file /workspace/repos.csv \
  --mode parallel \
  --max-jobs 8

# Check S3 transfer speeds
time aws s3 sync s3://source-bucket/test/ /tmp/test/

# Verify region matches
aws s3api get-bucket-location --bucket source-bucket
```

**Solutions:**

1. **Use Parallel Mode:**
   ```bash
   --mode parallel --max-jobs 8
   ```

2. **Increase Resources (ECS):**
   ```bash
   # Update task definition with more CPU/memory
   TaskCpu: 2048
   TaskMemory: 4096
   ```

3. **Use Same Region:**
   - Ensure S3 buckets and compute are in same region
   - Consider S3 Transfer Acceleration for cross-region

4. **Optimize Code Structure:**
   - Split large folders into smaller ones
   - Process in batches

### High Memory Usage

**Symptoms:**
- Container killed due to OOM
- Slow performance
- Swap usage

**Diagnostic Steps:**

```bash
# Monitor memory
docker stats <container-id>

# Check container memory limit
docker inspect <container-id> | grep -i memory

# ECS task memory
aws ecs describe-tasks \
  --cluster atx-runner-cluster \
  --tasks <task-arn> \
  --query 'tasks[0].containers[0].memory'
```

**Solutions:**

1. **Increase Memory Limits:**
   ```bash
   # ECS task definition
   TaskMemory: 4096  # or higher
   
   # Docker run
   docker run --memory=4g ...
   ```

2. **Process Fewer Folders in Parallel:**
   ```bash
   --mode parallel --max-jobs 4  # reduce from 8
   ```

3. **Use Serial Mode:**
   ```bash
   --mode serial
   ```

## Getting Help

If issues persist after following this guide:

1. **Review Documentation:**
   - [README.md](../README.md) - Main project documentation
   - [Deployment Guide](deployment.md) - Deployment instructions
   - [Exit Codes and Output Modes](exit-codes-and-output-modes.md) - Exit code reference
   - [Smoke Test Documentation](smoke-test.md) - Smoke test details
   - [Examples](../examples/README.md) - Usage examples

2. **Check Prerequisites:**
   - Docker 20.10+ installed and running
   - AWS credentials configured with S3 access
   - S3 buckets exist and are accessible
   - CSV file format is correct

3. **Gather Debug Information:**
   - Container logs
   - Execution logs from output directory
   - CSV configuration file
   - Environment details (OS, Docker version, AWS region)

4. **Common Solutions:**
   - Run smoke test: `docker run --rm atx-test-runner:latest --smoke-test`
   - Enable verbose mode: `--verbose`
   - Test with minimal CSV (single folder)
   - Verify AWS credentials: `aws sts get-caller-identity`
   - Check S3 access: `aws s3 ls s3://your-bucket/`
