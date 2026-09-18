# Lambda Terraform Module

Reusable Terraform module for deploying AWS Lambda functions with best-practice defaults.

## Features

- Three deployment modes: local ZIP, S3-hosted ZIP, and container image
- Auto-created CloudWatch log group with configurable retention and optional KMS encryption
- Least-privilege IAM role with scoped logging permissions
- Optional VPC connectivity, dead letter queue, X-Ray tracing
- Support for custom managed and inline IAM policies
- Consistent tagging via `common_tags`

## Usage

### Basic ZIP Deployment

```hcl
module "my_function" {
  source = "../modules/lambda"

  name_prefix   = "myapp-dev-"
  function_name = "process-orders"
  runtime       = "python3.12"
  handler       = "app.handler"
  filename      = "${path.module}/builds/process-orders.zip"
  source_code_hash = filebase64sha256("${path.module}/builds/process-orders.zip")

  common_tags = var.common_tags
}
```

### S3 Deployment

```hcl
module "my_function" {
  source = "../modules/lambda"

  name_prefix   = "myapp-dev-"
  function_name = "ingest-data"
  runtime       = "nodejs20.x"
  handler       = "index.handler"
  s3_bucket     = "my-deploy-bucket"
  s3_key        = "lambdas/ingest-data/v1.2.0.zip"

  common_tags = var.common_tags
}
```

### Container Image Deployment

```hcl
module "my_function" {
  source = "../modules/lambda"

  name_prefix   = "myapp-dev-"
  function_name = "ml-inference"
  package_type  = "Image"
  image_uri     = "123456789012.dkr.ecr.us-east-1.amazonaws.com/ml-inference:latest"
  memory_size   = 2048
  timeout       = 300

  common_tags = var.common_tags
}
```

### Full-Featured (VPC, KMS, DLQ, Tracing)

```hcl
module "my_function" {
  source = "../modules/lambda"

  name_prefix   = "myapp-prod-"
  function_name = "process-payments"
  runtime       = "python3.12"
  handler       = "app.handler"
  filename      = "${path.module}/builds/process-payments.zip"
  source_code_hash = filebase64sha256("${path.module}/builds/process-payments.zip")

  memory_size = 512
  timeout     = 60

  subnet_ids         = var.private_subnet_ids
  security_group_ids = [var.lambda_sg_id]

  environment_variables = {
    DB_HOST     = var.db_endpoint
    TABLE_NAME  = var.dynamodb_table
  }

  kms_key_arn            = var.kms_key_arn
  dead_letter_target_arn = var.dlq_arn
  tracing_mode           = "Active"

  policy_arns = [
    "arn:aws:iam::aws:policy/AmazonDynamoDBReadOnlyAccess"
  ]

  inline_policy_json = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = ["secretsmanager:GetSecretValue"]
        Resource = [var.db_secret_arn]
      }
    ]
  })

  log_retention_in_days = 90

  common_tags = var.common_tags
}
```

## Inputs

| Name | Type | Default | Description |
|------|------|---------|-------------|
| `name_prefix` | `string` | — | Prefix for resource names |
| `function_name` | `string` | — | Name of the Lambda function |
| `description` | `string` | `""` | Description of the Lambda function |
| `common_tags` | `map(string)` | `{}` | Common tags to apply to all resources |
| `runtime` | `string` | `null` | Lambda runtime identifier |
| `handler` | `string` | `null` | Function entrypoint in the code |
| `memory_size` | `number` | `128` | Memory in MB (128-10240) |
| `timeout` | `number` | `30` | Timeout in seconds (1-900) |
| `package_type` | `string` | `"Zip"` | Deployment package type (Zip or Image) |
| `filename` | `string` | `null` | Path to local ZIP file |
| `source_code_hash` | `string` | `null` | Base64-encoded SHA256 hash of ZIP |
| `s3_bucket` | `string` | `null` | S3 bucket for deployment package |
| `s3_key` | `string` | `null` | S3 key for deployment package |
| `s3_object_version` | `string` | `null` | S3 object version |
| `image_uri` | `string` | `null` | ECR image URI for container deployment |
| `publish` | `bool` | `false` | Publish as new version |
| `subnet_ids` | `list(string)` | `null` | Subnet IDs for VPC mode |
| `security_group_ids` | `list(string)` | `null` | Security group IDs for VPC mode |
| `environment_variables` | `map(string)` | `{}` | Environment variables |
| `kms_key_arn` | `string` | `null` | KMS key ARN for encryption |
| `log_retention_in_days` | `number` | `365` | CloudWatch log retention |
| `reserved_concurrent_executions` | `number` | `-1` | Reserved concurrency (-1 = unreserved) |
| `layers` | `list(string)` | `[]` | Lambda layer ARNs |
| `dead_letter_target_arn` | `string` | `null` | SQS/SNS ARN for failed invocations |
| `tracing_mode` | `string` | `null` | X-Ray tracing mode |
| `policy_arns` | `list(string)` | `[]` | Custom managed policy ARNs |
| `inline_policy_json` | `string` | `null` | Custom inline IAM policy JSON |

## Outputs

| Name | Description |
|------|-------------|
| `function_name` | Name of the Lambda function |
| `function_arn` | ARN of the Lambda function |
| `invoke_arn` | Invoke ARN (for API Gateway) |
| `qualified_arn` | Qualified ARN including version |
| `version` | Latest published version |
| `role_arn` | ARN of the execution IAM role |
| `role_name` | Name of the execution IAM role |
| `role_id` | ID of the execution IAM role |
| `log_group_name` | CloudWatch log group name |
| `log_group_arn` | CloudWatch log group ARN |

## Security

- IAM role follows least-privilege: only scoped CloudWatch Logs write access by default
- VPC access policy attached only when VPC is configured
- X-Ray policy attached only when tracing is enabled
- KMS encryption available for both environment variables and log group
- No wildcard resource permissions in default policies

## Best Practices

- Use `source_code_hash` to trigger redeployment on code changes
- Set `reserved_concurrent_executions` to prevent runaway scaling
- Enable `tracing_mode = "Active"` for production observability
- Configure `dead_letter_target_arn` to capture failed async invocations
- Use `kms_key_arn` for encrypting sensitive environment variables
