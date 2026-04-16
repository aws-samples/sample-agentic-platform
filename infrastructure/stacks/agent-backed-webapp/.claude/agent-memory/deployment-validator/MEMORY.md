# Deployment Validator Memory

## Stack: agent-backed-webapp

### Resource Locations
- All resources deployed in **us-east-1** region
- AWS profile `yiwenzhg+sandbox07-4-admin` has default region us-west-2, must specify `--region us-east-1` for AWS CLI commands
- Terraform state working directory: `/Users/yiwenzhg/Documents/aws/harness_engineering/sample-agentic-platform/infrastructure/stacks/agent-backed-webapp/`

### Resource Naming Convention
All resources use prefix `agent-webapp-` with a random suffix `ytb` for uniqueness.

### Key Resource Identifiers
- S3 Bucket: `terraform-20260416154151258000000002`
- CloudFront Distribution: `E2KAS21E44AW03`
- Cognito User Pool: `us-east-1_Htl8ETaia`
- Cognito Web Client: `3d718dbnpv6umvb4doctvj4krf`
- API Gateway: `gwfkdvkeqk`
- Lambda Function: `agent-webapp-agent-backend`
- Lambda IAM Role: `agent-webapp-agent-backend-role`

### Common Issues
- AWS CLI commands will fail if region is not specified (profile default is us-west-2)
- CloudFront distributions may show TLS protocol drift due to AWS managed updates
- Lambda placeholder deployment returns: `{"message": "Agent backend placeholder — deploy your code here"}`

### Health Check Patterns
- Lambda: Check State is "Active"
- API Gateway: Verify HTTP protocol type and JWT authorizer configuration
- Cognito: User Pool Status field returns null (normal behavior)
- CloudFront: Check Status is "Deployed" and Enabled is true
- S3: Verify PublicAccessBlock all settings are true
