# Build and Test Documentation

## Overview

This document describes how to build and test the ATX Container Test Runner Docker image. The build and test process validates that the container is properly configured with all required components and can execute ATX transformations successfully.

## Quick Start

```bash
# Ensure Docker is running
docker info

# Build and test with defaults
./scripts/build-and-test.sh

# Build without cache (clean build)
./scripts/build-and-test.sh --no-cache

# Build with verbose output
./scripts/build-and-test.sh --verbose
```

## Prerequisites

### Required

- **Docker**: Version 20.10 or later
  - Install: https://docs.docker.com/get-docker/
  - Verify: `docker --version`
  - Ensure Docker daemon is running: `docker info`

### Optional (for S3 integration test)

- **AWS CLI**: Configured with credentials
  - Install: https://docs.aws.amazon.com/cli/latest/userguide/getting-started-install.html
  - Configure: `aws configure`
  - Verify: `aws sts get-caller-identity`

- **S3 Bucket**: With sample Progress code
  - Create bucket: `aws s3 mb s3://my-test-bucket`
  - Upload sample code: `aws s3 sync ./examples/sample-code s3://my-test-bucket/test/`

## Build and Test Script

### Usage

```bash
./scripts/build-and-test.sh [OPTIONS]
```

### Options

| Option | Description | Default |
|--------|-------------|---------|
| `--image-name <name>` | Docker image name | `atx-test-runner` |
| `--image-tag <tag>` | Docker image tag | `latest` |
| `--output-dir <dir>` | Output directory for test results | `./build_test_results` |
| `--max-size-mb <size>` | Maximum acceptable image size in MB | `2000` (2GB) |
| `--no-cache` | Build without using Docker cache | `false` |
| `--skip-build` | Skip Docker build step | `false` |
| `--skip-smoke-test` | Skip smoke test | `false` |
| `--skip-s3-test` | Skip S3 integration test | `false` |
| `--verbose` | Enable verbose output | `false` |
| `--help` | Show help message | - |

### Examples

```bash
# Standard build and test
./scripts/build-and-test.sh

# Clean build (no cache)
./scripts/build-and-test.sh --no-cache

# Build with custom image name and tag
./scripts/build-and-test.sh --image-name my-atx-runner --image-tag v1.0.0

# Test existing image without rebuilding
./scripts/build-and-test.sh --skip-build --image-tag v1.0.0

# Build and skip S3 test (no AWS setup)
./scripts/build-and-test.sh --skip-s3-test

# Verbose output for debugging
./scripts/build-and-test.sh --verbose

# Custom output directory
./scripts/build-and-test.sh --output-dir ./my-test-results
```

## Build Process

### Step 1: Docker Image Build

The script builds the Docker image using the Dockerfile in the project root.

**What it does:**
- Validates Dockerfile exists
- Executes `docker build` command
- Captures build logs
- Reports build duration

**Build command:**
```bash
docker build -t atx-test-runner:latest -f ./Dockerfile .
```

**Expected output:**
```
==========================================
STEP 1: Building Docker Image
==========================================
[INFO] Building image: atx-test-runner:latest
[INFO] Build context: /path/to/project
[INFO] Starting Docker build (this may take several minutes)...
[SUCCESS] Docker image built successfully
[INFO]   Image: atx-test-runner:latest
[INFO]   Build time: 180s
```

**Build time:** Typically 2-5 minutes depending on:
- Network speed (downloading packages)
- Docker cache availability
- System resources

### Step 2: Image Size Verification

The script verifies the built image size is within acceptable limits.

**What it checks:**
- Image size in MB
- Compares against maximum allowed size (default: 2000 MB)
- Reports size as percentage of maximum

**Expected output:**
```
==========================================
STEP 2: Verifying Image Size
==========================================
[INFO] Image size: 1250 MB
[INFO] Maximum allowed: 2000 MB
[SUCCESS] Image size is acceptable (62% of maximum)
```

**Typical image sizes:**
- Base Ubuntu 22.04: ~80 MB
- With system dependencies: ~200 MB
- With ATX CLI: ~500 MB
- With AWS CLI: ~600 MB
- Final image: ~1200-1500 MB

**If size exceeds limit:**
- Review Dockerfile for optimization opportunities
- Remove unnecessary packages
- Use multi-stage builds
- Clean up apt cache and temporary files

### Step 3: Component Verification

The script verifies all required components are installed and accessible.

**Components checked:**
1. **ATX CLI**
   - Command exists: `command -v atx`
   - Version check: `atx --version`
   - Expected location: `/opt/atx/atx` or in PATH

2. **AWS CLI**
   - Command exists: `command -v aws`
   - Version check: `aws --version`
   - Expected version: AWS CLI v2

3. **Scripts**
   - `/usr/local/bin/atx-orchestrator.sh`
   - `/usr/local/bin/s3-integration.sh`
   - `/usr/local/bin/smoke-test.sh`
   - `/usr/local/bin/csv-parser.sh`
   - All must be present and executable

**Expected output:**
```
==========================================
STEP 3: Verifying Component Installation
==========================================
[INFO] Checking ATX CLI installation...
[SUCCESS] ATX CLI is installed
[INFO]   Version: 1.0.1318.0
[INFO] Checking AWS CLI installation...
[SUCCESS] AWS CLI is installed
[INFO]   aws-cli/2.15.0 Python/3.11.6
[INFO] Checking scripts are installed...
[SUCCESS]   /usr/local/bin/atx-orchestrator.sh is present and executable
[SUCCESS]   /usr/local/bin/s3-integration.sh is present and executable
[SUCCESS]   /usr/local/bin/smoke-test.sh is present and executable
[SUCCESS]   /usr/local/bin/csv-parser.sh is present and executable
[SUCCESS] All components are properly installed
```

### Step 4: Smoke Test

The script runs the smoke test to verify ATX can execute transformations.

**What it does:**
- Runs container with smoke test flag
- Creates minimal Progress code sample
- Executes ATX transformation
- Verifies transformation completes successfully

**Smoke test command:**
```bash
docker run --rm \
  -v ./build_test_results/smoke_test:/workspace/results \
  atx-test-runner:latest \
  --smoke-test \
  --output-dir /workspace/results
```

**Expected output:**
```
==========================================
STEP 4: Running Smoke Test
==========================================
[INFO] Executing smoke test in container...
[INFO] This verifies ATX can execute transformations
[SUCCESS] Smoke test passed
[INFO]   Duration: 15s
[INFO]   Results: ./build_test_results/smoke_test/
[INFO]   Log file: ./build_test_results/smoke_test/smoke_test.log
```

**Smoke test validates:**
- ATX CLI is accessible in container
- AWS CLI is accessible in container
- Test Progress code can be created
- ATX can execute a transformation
- Transformation completes without errors

See [Smoke Test Documentation](smoke-test.md) for detailed information.

### Step 5: S3 Integration Test (Optional)

The script can optionally run an S3 integration test to verify end-to-end functionality.

**Status:** Currently skipped by default (not yet implemented)

**When implemented, it will:**
1. Check AWS credentials are configured
2. Create or use existing S3 test bucket
3. Upload sample Progress code to S3
4. Create CSV with S3 paths
5. Run orchestrator with CSV
6. Verify results are uploaded to S3
7. Clean up test resources

**To skip:** Use `--skip-s3-test` flag (default behavior currently)

## Output Files

The build and test process generates several output files in the output directory (default: `./build_test_results/`).

### Directory Structure

```
build_test_results/
├── build.log                    # Docker build output
├── atx_version.txt              # ATX CLI version info
├── aws_version.txt              # AWS CLI version info
├── summary.txt                  # Summary report
└── smoke_test/                  # Smoke test results
    ├── smoke_test.log           # Smoke test execution log
    └── smoke_test_failure/      # Preserved on failure
        ├── workspace/
        │   └── test.p           # Test Progress code
        └── README.txt           # Debugging guide
```

### Summary Report

The `summary.txt` file contains a comprehensive summary of the build and test process:

```
ATX Container Build and Test Summary
====================================
Generated: 2025-12-08 14:30:00

IMAGE INFORMATION
-----------------
Image Name: atx-test-runner:latest
Image ID: sha256:abc123...
Image Size: 1250 MB
Created: 2025-12-08T14:25:00Z

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
- Build log: ./build_test_results/build.log
- ATX version: ./build_test_results/atx_version.txt
- AWS version: ./build_test_results/aws_version.txt
- Smoke test results: ./build_test_results/smoke_test/
- Summary: ./build_test_results/summary.txt

NEXT STEPS
----------
1. Push image to ECR:
   docker tag atx-test-runner:latest <account>.dkr.ecr.<region>.amazonaws.com/atx-test-runner:latest
   docker push <account>.dkr.ecr.<region>.amazonaws.com/atx-test-runner:latest

2. Deploy to ECS/EKS:
   See docs/deployment.md for deployment instructions

3. Run with sample data:
   docker run --rm -v $(pwd)/examples:/data atx-test-runner:latest --csv-file /data/single-customer.csv
```

## Exit Codes

The build and test script uses specific exit codes to indicate different failure types:

| Exit Code | Meaning | Description |
|-----------|---------|-------------|
| 0 | Success | All tests passed, image is ready |
| 1 | Build failed | Docker build failed |
| 2 | Size check failed | Image size exceeds maximum allowed |
| 3 | Component verification failed | Required component missing or not accessible |
| 4 | Smoke test failed | Smoke test execution failed |
| 5 | S3 test failed | S3 integration test failed |
| 10 | Docker not available | Docker not installed or daemon not running |
| 11 | Invalid arguments | Invalid command-line arguments |

## Troubleshooting

### Docker Daemon Not Running

**Symptoms:**
```
[ERROR] Docker daemon is not running
[ERROR] Please start Docker Desktop or the Docker daemon
```

**Solutions:**
- **macOS/Windows**: Start Docker Desktop application
- **Linux**: Start Docker daemon: `sudo systemctl start docker`
- Verify: `docker info`

### Build Failed

**Symptoms:**
```
[ERROR] Docker build failed
[ERROR] See build log: ./build_test_results/build.log
```

**Common causes:**
1. **Network issues**: Cannot download packages
   - Check internet connectivity
   - Try again with `--no-cache`

2. **Disk space**: Insufficient disk space
   - Check: `df -h`
   - Clean up: `docker system prune -a`

3. **Dockerfile errors**: Syntax or command errors
   - Review build log
   - Check Dockerfile syntax
   - Verify package names and URLs

**Solutions:**
1. Review build log: `cat ./build_test_results/build.log`
2. Try clean build: `./scripts/build-and-test.sh --no-cache`
3. Check Docker disk space: `docker system df`
4. Clean up old images: `docker system prune -a`

### Image Size Too Large

**Symptoms:**
```
[ERROR] Image size exceeds maximum allowed size
[ERROR]   Actual: 2500 MB
[ERROR]   Maximum: 2000 MB
```

**Solutions:**
1. **Increase limit** (if acceptable):
   ```bash
   ./scripts/build-and-test.sh --max-size-mb 3000
   ```

2. **Optimize Dockerfile**:
   - Combine RUN commands to reduce layers
   - Clean up apt cache: `rm -rf /var/lib/apt/lists/*`
   - Remove unnecessary packages
   - Use multi-stage builds

3. **Review layers**:
   ```bash
   docker history atx-test-runner:latest --human
   ```

### Component Verification Failed

**Symptoms:**
```
[ERROR] ATX CLI is not installed or not accessible
[ERROR] Some components are missing or not properly installed
```

**Solutions:**
1. **Check Dockerfile**: Verify ATX installation commands
2. **Check PATH**: Ensure ATX is in PATH or at expected location
3. **Manual verification**:
   ```bash
   docker run --rm atx-test-runner:latest sh -c "command -v atx && atx --version"
   ```
4. **Review installation logs**: Check build.log for errors

### Smoke Test Failed

**Symptoms:**
```
[ERROR] Smoke test failed (exit code: 4)
```

**Common causes:**
1. **ATX not accessible**: ATX CLI not in PATH
2. **Git requirement**: ATX requires code in git repository
3. **Authentication**: Midway cookie expired or AWS credentials not configured
4. **Network issues**: Cannot reach ATX service endpoints

**Solutions:**
1. **Review smoke test log**:
   ```bash
   cat ./build_test_results/smoke_test/smoke_test.log
   ```

2. **Check preserved artifacts**:
   ```bash
   ls -la ./build_test_results/smoke_test/smoke_test_failure/
   ```

3. **Run smoke test manually**:
   ```bash
   docker run --rm -it atx-test-runner:latest --smoke-test --verbose
   ```

4. **Check ATX authentication**:
   ```bash
   docker run --rm atx-test-runner:latest sh -c "atx --version"
   ```

See [Smoke Test Documentation](smoke-test.md) for detailed troubleshooting.

## Manual Testing

### Test Individual Components

```bash
# Test ATX CLI
docker run --rm atx-test-runner:latest sh -c "atx --version"

# Test AWS CLI
docker run --rm atx-test-runner:latest sh -c "aws --version"

# Test scripts are present
docker run --rm atx-test-runner:latest sh -c "ls -la /usr/local/bin/*.sh"

# Test orchestrator help
docker run --rm atx-test-runner:latest --help
```

### Test with Sample Data

```bash
# Run with single customer CSV
docker run --rm \
  -v $(pwd)/examples:/data \
  -v $(pwd)/test_results:/workspace/results \
  atx-test-runner:latest \
  --csv-file /data/single-customer.csv \
  --output-dir /workspace/results

# Run with verbose output
docker run --rm \
  -v $(pwd)/examples:/data \
  -v $(pwd)/test_results:/workspace/results \
  atx-test-runner:latest \
  --csv-file /data/single-customer.csv \
  --output-dir /workspace/results \
  --verbose
```

### Interactive Testing

```bash
# Start interactive shell in container
docker run --rm -it atx-test-runner:latest sh

# Inside container, test commands:
atx --version
aws --version
ls -la /usr/local/bin/
cat /usr/local/bin/smoke-test.sh
```

## CI/CD Integration

### GitHub Actions

```yaml
name: Build and Test ATX Container

on: [push, pull_request]

jobs:
  build-and-test:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v3
      
      - name: Set up Docker Buildx
        uses: docker/setup-buildx-action@v2
      
      - name: Build and test
        run: ./scripts/build-and-test.sh --verbose
      
      - name: Upload test results
        if: always()
        uses: actions/upload-artifact@v3
        with:
          name: build-test-results
          path: build_test_results/
      
      - name: Upload summary
        if: always()
        uses: actions/upload-artifact@v3
        with:
          name: summary
          path: build_test_results/summary.txt
```

### GitLab CI

```yaml
build-and-test:
  stage: test
  image: docker:latest
  services:
    - docker:dind
  script:
    - chmod +x scripts/build-and-test.sh
    - ./scripts/build-and-test.sh --verbose
  artifacts:
    when: always
    paths:
      - build_test_results/
    expire_in: 1 week
```

### Jenkins Pipeline

```groovy
pipeline {
    agent any
    
    stages {
        stage('Build and Test') {
            steps {
                sh 'chmod +x scripts/build-and-test.sh'
                sh './scripts/build-and-test.sh --verbose'
            }
        }
    }
    
    post {
        always {
            archiveArtifacts artifacts: 'build_test_results/**/*', allowEmptyArchive: true
            publishHTML([
                reportDir: 'build_test_results',
                reportFiles: 'summary.txt',
                reportName: 'Build and Test Summary'
            ])
        }
    }
}
```

## Best Practices

1. **Always run tests after building**
   - Don't skip smoke test
   - Verify all components before deployment

2. **Use clean builds for releases**
   - Use `--no-cache` for production builds
   - Ensures reproducible builds

3. **Monitor image size**
   - Keep image size reasonable
   - Optimize Dockerfile regularly

4. **Preserve test artifacts**
   - Keep build_test_results for debugging
   - Archive in CI/CD pipelines

5. **Test locally before CI/CD**
   - Run build-and-test.sh locally
   - Catch issues early

6. **Version your images**
   - Use semantic versioning
   - Tag with git commit SHA

7. **Document custom configurations**
   - Document any Dockerfile changes
   - Update this documentation

## Next Steps

After successful build and test:

1. **Tag image for registry**:
   ```bash
   docker tag atx-test-runner:latest <account>.dkr.ecr.<region>.amazonaws.com/atx-test-runner:v1.0.0
   ```

2. **Push to ECR**:
   ```bash
   aws ecr get-login-password --region <region> | docker login --username AWS --password-stdin <account>.dkr.ecr.<region>.amazonaws.com
   docker push <account>.dkr.ecr.<region>.amazonaws.com/atx-test-runner:v1.0.0
   ```

3. **Deploy to ECS/EKS**:
   - See [Deployment Guide](deployment.md)

4. **Run with production data**:
   - Create production CSV
   - Configure AWS credentials
   - Run orchestrator

## Requirements Validation

This build and test process validates the following requirements:

- **Requirement 7.5**: Dockerfile builds custom image with ATX and dependencies
- **Requirement 10.1**: Smoke test command executes sample transformation
- **Requirement 10.3**: Verifies ATX is properly installed and accessible
- **Requirement 10.4**: Exits with code 0 on success, displays success message
- **Requirement 1.3**: Container can execute ATX transformations
- **Requirement 1.4**: Results are captured and accessible

## Related Documentation

- [Smoke Test Documentation](smoke-test.md) - Detailed smoke test information
- [Deployment Guide](deployment.md) - Container deployment instructions
- [Troubleshooting Guide](troubleshooting.md) - General troubleshooting
- [Scripts README](../scripts/README.md) - Script documentation

