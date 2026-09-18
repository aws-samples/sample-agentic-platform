# Quick Start: Deploy to ECS and Test

This guide will help you deploy the ATX Container Test Runner to AWS ECS Fargate and test it with sample Progress code.

## Overview

We'll use CloudFormation to deploy a complete ECS infrastructure including:
- VPC with public subnets
- ECS Fargate cluster
- IAM roles
- ECR repository
- CloudWatch Logs

**Estimated time**: 20-25 minutes

## Step 1: Prerequisites Check (2 minutes)

```bash
# Verify AWS CLI
aws --version
# Expected: aws-cli/2.x.x or higher

# Verify Docker
docker --version
# Expected: Docker version 20.10.x or higher

# Check AWS credentials and get account info
aws sts get-caller-identity

# Set environment variables
export AWS_REGION="us-east-1"  # Change to your preferred region
export AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)

echo "✓ AWS Account ID: ${AWS_ACCOUNT_ID}"
echo "✓ AWS Region: ${AWS_REGION}"
```

## Step 2: Create S3 Buckets (2 minutes)

```bash
# Create unique bucket names
export SOURCE_BUCKET="atx-test-source-${AWS_ACCOUNT_ID}"
export RESULTS_BUCKET="atx-test-results-${AWS_ACCOUNT_ID}"

# Create source bucket
aws s3 mb s3://${SOURCE_BUCKET} --region ${AWS_REGION}
echo "✓ Created source bucket: ${SOURCE_BUCKET}"

# Create results bucket
aws s3 mb s3://${RESULTS_BUCKET} --region ${AWS_REGION}
echo "✓ Created results bucket: ${RESULTS_BUCKET}"

# Verify buckets
aws s3 ls | grep atx-test
```

## Step 3: Create Sample Progress Code (1 minute)

```bash
# Create test directory
mkdir -p test-progress-code

# Create a sample Progress file
cat > test-progress-code/sample.p << 'EOF'
/* Sample Progress Code for ATX Testing */
DEFINE VARIABLE cCustomerName AS CHARACTER NO-UNDO.
DEFINE VARIABLE iOrderCount AS INTEGER NO-UNDO.
DEFINE VARIABLE dTotalAmount AS DECIMAL NO-UNDO.

/* Sample procedure */
PROCEDURE ProcessOrder:
    DEFINE INPUT PARAMETER pcOrderId AS CHARACTER NO-UNDO.
    DEFINE INPUT PARAMETER pdAmount AS DECIMAL NO-UNDO.
    
    ASSIGN 
        iOrderCount = iOrderCount + 1
        dTotalAmount = dTotalAmount + pdAmount.
    
    MESSAGE "Processed order: " + pcOrderId 
            " Amount: " + STRING(pdAmount)
            VIEW-AS ALERT-BOX.
END PROCEDURE.

/* Main block */
DO:
    ASSIGN 
        cCustomerName = "Test Customer"
        iOrderCount = 0
        dTotalAmount = 0.00.
    
    RUN ProcessOrder(INPUT "ORD-001", INPUT 100.50).
    RUN ProcessOrder(INPUT "ORD-002", INPUT 250.75).
    
    MESSAGE "Customer: " + cCustomerName SKIP
            "Total Orders: " + STRING(iOrderCount) SKIP
            "Total Amount: $" + STRING(dTotalAmount, ">>>,>>9.99")
            VIEW-AS ALERT-BOX.
END.
EOF

echo "✓ Created sample Progress code"
```

## Step 4: Upload Sample Code to S3 (1 minute)

```bash
# Upload to S3
aws s3 sync test-progress-code/ s3://${SOURCE_BUCKET}/customer1/folder1/

# Verify upload
echo "✓ Uploaded files:"
aws s3 ls s3://${SOURCE_BUCKET}/customer1/folder1/
```

## Step 5: Build Docker Image (5 minutes)

```bash
# Build the image
echo "Building Docker image..."
docker build -t atx-test-runner:latest .

# Verify build
docker images | grep atx-test-runner

# Run local smoke test
echo "Running smoke test..."
docker run --rm atx-test-runner:latest --smoke-test

# Expected output:
# ==========================================
# ATX Container Smoke Test
# ==========================================
# ✓ ATX CLI found
# ✓ AWS CLI found
# ✓ Test code created
# ✓ ATX transformation successful
# SMOKE TEST PASSED
```

## Step 6: Push Image to ECR (3 minutes)

```bash
# Use the automated script
chmod +x scripts/push-to-ecr.sh
./scripts/push-to-ecr.sh ${AWS_ACCOUNT_ID} ${AWS_REGION}

# The script will:
# ✓ Authenticate to ECR
# ✓ Create repository (with image scanning and encryption)
# ✓ Tag image with version and latest
# ✓ Push to ECR
# ✓ Verify push

# Save ECR URI for later
export ECR_URI="${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com/atx-test-runner"
echo "✓ Image pushed to: ${ECR_URI}:latest"
```

## Step 7: Deploy ECS Infrastructure with CloudFormation (8-10 minutes)

```bash
# Deploy the complete stack
echo "Deploying CloudFormation stack..."
aws cloudformation create-stack \
  --stack-name atx-test-runner \
  --template-body file://deployment/cloudformation-complete-stack.yaml \
  --parameters \
    ParameterKey=SourceBucketName,ParameterValue=${SOURCE_BUCKET} \
    ParameterKey=ResultsBucketName,ParameterValue=${RESULTS_BUCKET} \
    ParameterKey=ImageVersion,ParameterValue=latest \
    ParameterKey=EnvironmentName,ParameterValue=test \
    ParameterKey=MaxParallelJobs,ParameterValue=4 \
    ParameterKey=TaskCpu,ParameterValue=2048 \
    ParameterKey=TaskMemory,ParameterValue=4096 \
  --capabilities CAPABILITY_NAMED_IAM \
  --region ${AWS_REGION}

echo "✓ Stack creation initiated"
echo "⏳ Waiting for stack to complete (this takes 5-10 minutes)..."
echo "   You can monitor progress in the AWS Console:"
echo "   https://console.aws.amazon.com/cloudformation/home?region=${AWS_REGION}#/stacks"

# Wait for completion
aws cloudformation wait stack-create-complete \
  --stack-name atx-test-runner \
  --region ${AWS_REGION}

echo "✓ Stack created successfully!"
```

## Step 8: Get Stack Outputs (1 minute)

```bash
# Get all outputs
echo "Stack Outputs:"
aws cloudformation describe-stacks \
  --stack-name atx-test-runner \
  --region ${AWS_REGION} \
  --query 'Stacks[0].Outputs[*].[OutputKey,OutputValue]' \
  --output table

# Save important values
export CLUSTER_NAME=$(aws cloudformation describe-stacks \
  --stack-name atx-test-runner \
  --query 'Stacks[0].Outputs[?OutputKey==`ClusterName`].OutputValue' \
  --output text \
  --region ${AWS_REGION})

export TASK_DEFINITION=$(aws cloudformation describe-stacks \
  --stack-name atx-test-runner \
  --query 'Stacks[0].Outputs[?OutputKey==`TaskDefinitionArn`].OutputValue' \
  --output text \
  --region ${AWS_REGION})

export SUBNET_1=$(aws cloudformation describe-stacks \
  --stack-name atx-test-runner \
  --query 'Stacks[0].Outputs[?OutputKey==`Subnet1Id`].OutputValue' \
  --output text \
  --region ${AWS_REGION})

export SUBNET_2=$(aws cloudformation describe-stacks \
  --stack-name atx-test-runner \
  --query 'Stacks[0].Outputs[?OutputKey==`Subnet2Id`].OutputValue' \
  --output text \
  --region ${AWS_REGION})

export SECURITY_GROUP=$(aws cloudformation describe-stacks \
  --stack-name atx-test-runner \
  --query 'Stacks[0].Outputs[?OutputKey==`SecurityGroupId`].OutputValue' \
  --output text \
  --region ${AWS_REGION})

echo "✓ Cluster: ${CLUSTER_NAME}"
echo "✓ Task Definition: ${TASK_DEFINITION}"
echo "✓ Subnets: ${SUBNET_1}, ${SUBNET_2}"
echo "✓ Security Group: ${SECURITY_GROUP}"
```

## Step 9: Create CSV Configuration (1 minute)

```bash
# Create CSV file
cat > test-repos.csv << EOF
s3_path,build_command,transformation_name,output_s3_path
s3://${SOURCE_BUCKET}/customer1/folder1/,noop,Comprehensive-Codebase-Analysis,s3://${RESULTS_BUCKET}/customer1/folder1/
EOF

echo "✓ Created CSV configuration:"
cat test-repos.csv

# Upload to S3 (optional - we'll pass it directly to the task)
aws s3 cp test-repos.csv s3://${SOURCE_BUCKET}/config/test-repos.csv
echo "✓ Uploaded CSV to S3"
```

## Step 10: Run ECS Task (2 minutes)

```bash
# Run the task
echo "Running ECS task..."
TASK_ARN=$(aws ecs run-task \
  --cluster ${CLUSTER_NAME} \
  --task-definition ${TASK_DEFINITION} \
  --launch-type FARGATE \
  --network-configuration "awsvpcConfiguration={
    subnets=[${SUBNET_1},${SUBNET_2}],
    securityGroups=[${SECURITY_GROUP}],
    assignPublicIp=ENABLED
  }" \
  --region ${AWS_REGION} \
  --query 'tasks[0].taskArn' \
  --output text)

echo "✓ Task started: ${TASK_ARN}"
echo "⏳ Task is running..."

# Get short task ID for logs
TASK_ID=$(echo ${TASK_ARN} | awk -F/ '{print $NF}')
echo "   Task ID: ${TASK_ID}"
```

## Step 11: Monitor Task Execution (3-5 minutes)

```bash
# Check task status
echo "Checking task status..."
aws ecs describe-tasks \
  --cluster ${CLUSTER_NAME} \
  --tasks ${TASK_ARN} \
  --region ${AWS_REGION} \
  --query 'tasks[0].[lastStatus,desiredStatus,stopCode,stoppedReason]' \
  --output table

# Stream logs (in a new terminal or wait a moment for logs to appear)
echo "Streaming CloudWatch logs..."
echo "Press Ctrl+C to stop streaming"
aws logs tail /ecs/test-atx-test-runner --follow --region ${AWS_REGION}

# Alternative: Get logs without streaming
# aws logs tail /ecs/test-atx-test-runner --since 5m --region ${AWS_REGION}
```

### Monitor in AWS Console

You can also monitor in the AWS Console:
- **ECS Tasks**: https://console.aws.amazon.com/ecs/home?region=${AWS_REGION}#/clusters/${CLUSTER_NAME}/tasks
- **CloudWatch Logs**: https://console.aws.amazon.com/cloudwatch/home?region=${AWS_REGION}#logsV2:log-groups/log-group/$252Fecs$252Ftest-atx-test-runner

## Step 12: Check Results (2 minutes)

```bash
# Wait for task to complete
echo "Waiting for task to complete..."
aws ecs wait tasks-stopped \
  --cluster ${CLUSTER_NAME} \
  --tasks ${TASK_ARN} \
  --region ${AWS_REGION}

echo "✓ Task completed"

# Check final task status
aws ecs describe-tasks \
  --cluster ${CLUSTER_NAME} \
  --tasks ${TASK_ARN} \
  --region ${AWS_REGION} \
  --query 'tasks[0].[lastStatus,stopCode,stoppedReason,containers[0].exitCode]' \
  --output table

# List results in S3
echo "Results in S3:"
aws s3 ls s3://${RESULTS_BUCKET}/ --recursive

# Download results
mkdir -p results
aws s3 sync s3://${RESULTS_BUCKET}/ ./results/

echo "✓ Results downloaded to ./results/"

# View the analysis (if it exists)
if [ -f results/customer1/folder1/analysis.md ]; then
    echo "ATX Analysis Output:"
    cat results/customer1/folder1/analysis.md
else
    echo "Checking for other result files..."
    find results/ -type f
fi
```

## Step 13: Run Another Test (Optional)

```bash
# Run the task again with different parameters
aws ecs run-task \
  --cluster ${CLUSTER_NAME} \
  --task-definition ${TASK_DEFINITION} \
  --launch-type FARGATE \
  --network-configuration "awsvpcConfiguration={
    subnets=[${SUBNET_1},${SUBNET_2}],
    securityGroups=[${SECURITY_GROUP}],
    assignPublicIp=ENABLED
  }" \
  --overrides '{
    "containerOverrides": [{
      "name": "atx-test-runner",
      "command": [
        "/usr/local/bin/atx-orchestrator.sh",
        "--csv-file", "/config/repos.csv",
        "--mode", "parallel",
        "--max-jobs", "8",
        "--verbose"
      ]
    }]
  }' \
  --region ${AWS_REGION}
```

## Troubleshooting

### Task fails to start

```bash
# Check task events
aws ecs describe-tasks \
  --cluster ${CLUSTER_NAME} \
  --tasks ${TASK_ARN} \
  --region ${AWS_REGION} \
  --query 'tasks[0].containers[0].[reason,lastStatus]'

# Check CloudWatch logs
aws logs tail /ecs/test-atx-test-runner --since 10m --region ${AWS_REGION}
```

### No results in S3

```bash
# Check if task completed successfully
aws ecs describe-tasks \
  --cluster ${CLUSTER_NAME} \
  --tasks ${TASK_ARN} \
  --region ${AWS_REGION} \
  --query 'tasks[0].containers[0].exitCode'

# Check logs for errors
aws logs filter-log-events \
  --log-group-name /ecs/test-atx-test-runner \
  --filter-pattern "ERROR" \
  --region ${AWS_REGION}
```

### IAM permission issues

```bash
# Verify task role has S3 permissions
aws iam get-role-policy \
  --role-name test-atx-task-role \
  --policy-name S3Access \
  --region ${AWS_REGION}
```

### Network issues

```bash
# Verify security group allows outbound traffic
aws ec2 describe-security-groups \
  --group-ids ${SECURITY_GROUP} \
  --region ${AWS_REGION} \
  --query 'SecurityGroups[0].IpPermissionsEgress'

# Verify subnets have internet access
aws ec2 describe-route-tables \
  --filters "Name=association.subnet-id,Values=${SUBNET_1}" \
  --region ${AWS_REGION} \
  --query 'RouteTables[0].Routes'
```

## Cleanup

When you're done testing, clean up all resources:

```bash
# Delete CloudFormation stack (this removes ECS, VPC, IAM roles, etc.)
echo "Deleting CloudFormation stack..."
aws cloudformation delete-stack \
  --stack-name atx-test-runner \
  --region ${AWS_REGION}

echo "⏳ Waiting for stack deletion..."
aws cloudformation wait stack-delete-complete \
  --stack-name atx-test-runner \
  --region ${AWS_REGION}

echo "✓ Stack deleted"

# Empty and delete S3 buckets
echo "Cleaning up S3 buckets..."
aws s3 rm s3://${SOURCE_BUCKET} --recursive
aws s3 rb s3://${SOURCE_BUCKET}

aws s3 rm s3://${RESULTS_BUCKET} --recursive
aws s3 rb s3://${RESULTS_BUCKET}

echo "✓ S3 buckets deleted"

# Delete ECR images and repository
echo "Cleaning up ECR..."
aws ecr batch-delete-image \
  --repository-name atx-test-runner \
  --image-ids imageTag=latest imageTag=0.1.0 \
  --region ${AWS_REGION} 2>/dev/null || true

aws ecr delete-repository \
  --repository-name atx-test-runner \
  --force \
  --region ${AWS_REGION}

echo "✓ ECR repository deleted"

# Clean up local files
rm -rf test-progress-code results test-repos.csv

echo "✓ Cleanup complete!"
```

## Quick Reference Commands

```bash
# View running tasks
aws ecs list-tasks --cluster ${CLUSTER_NAME} --region ${AWS_REGION}

# Stream logs
aws logs tail /ecs/test-atx-test-runner --follow --region ${AWS_REGION}

# Check results
aws s3 ls s3://${RESULTS_BUCKET}/ --recursive

# Stop a running task
aws ecs stop-task --cluster ${CLUSTER_NAME} --task ${TASK_ARN} --region ${AWS_REGION}

# Update task definition (after code changes)
# 1. Build and push new image
docker build -t atx-test-runner:latest .
./scripts/push-to-ecr.sh ${AWS_ACCOUNT_ID} ${AWS_REGION}

# 2. Update CloudFormation stack
aws cloudformation update-stack \
  --stack-name atx-test-runner \
  --use-previous-template \
  --parameters \
    ParameterKey=SourceBucketName,UsePreviousValue=true \
    ParameterKey=ResultsBucketName,UsePreviousValue=true \
    ParameterKey=ImageVersion,ParameterValue=latest \
    ParameterKey=EnvironmentName,UsePreviousValue=true \
  --capabilities CAPABILITY_NAMED_IAM \
  --region ${AWS_REGION}
```

## Next Steps

1. **Test with your own Progress code**: Upload your code to S3 and update the CSV
2. **Test parallel execution**: Add multiple folders to the CSV
3. **Set up scheduled execution**: Use EventBridge to run tasks on a schedule
4. **Configure monitoring**: Set up CloudWatch alarms for task failures
5. **Optimize costs**: Use Fargate Spot for non-critical workloads

## Additional Resources

- [Complete Deployment Guide](docs/deployment-guide.md)
- [CloudFormation Template Details](deployment/cloudformation-complete-stack.yaml)
- [Troubleshooting Guide](docs/troubleshooting.md)
- [ECS Documentation](https://docs.aws.amazon.com/ecs/)

## Summary

You've successfully:
- ✅ Built and pushed a Docker image to ECR
- ✅ Deployed a complete ECS Fargate infrastructure
- ✅ Run an ATX transformation on sample Progress code
- ✅ Retrieved results from S3

The infrastructure is now ready for production use with your own Progress code!
