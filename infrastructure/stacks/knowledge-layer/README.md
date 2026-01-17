# Knowledge Layer Stack

This stack creates the knowledge base infrastructure for the agentic platform, including:
- AWS Bedrock Knowledge Base with Nova 2 multimodal embeddings
- S3 Vectors bucket and index for semantic search
- IAM roles and policies for Bedrock
- Parameter Store integration for configuration

## Architecture

The knowledge layer is deployed separately from the platform-eks stack to allow:
- Independent deployment and updates
- Different lifecycle management
- Potential sharing across multiple EKS clusters or environments
- Clean separation of concerns

## Resources Created

1. **S3 Vectors Bucket** - Stores document vectors for semantic search
2. **S3 Vectors Index** - Semantic search index with configurable distance metric
3. **Bedrock Knowledge Base** - Configured with Nova 2 multimodal embeddings (1024 dimensions)
4. **IAM Role** - Allows Bedrock to access S3 Vectors and invoke embedding models
5. **Parameter Store** - Stores configuration that flows to Kubernetes ConfigMaps

## Configuration Flow

```
Terraform (knowledge-layer)
  → AWS Parameter Store (/agentic-platform/config)
  → Kubernetes ConfigMap (agentic-platform-config)
  → Pod Environment Variables (KNOWLEDGE_BASE_ID)
  → MCP Server Application
```

## Prerequisites

- AWS CLI configured with appropriate credentials
- Terraform >= 1.0
- Access to AWS Bedrock (Nova 2 model enabled in your region)
- Existing Parameter Store module (shared infrastructure)

## Deployment

### First Time Setup

1. **Initialize Terraform**
   ```bash
   cd infrastructure/stacks/knowledge-layer
   terraform init
   ```

2. **Review Configuration**

   Check `variables.tf` for default values. You can override them by:
   - Creating a `terraform.tfvars` file
   - Using `-var` flags
   - Using environment variables (TF_VAR_*)

3. **Plan Deployment**
   ```bash
   terraform plan
   ```

4. **Apply Changes**
   ```bash
   terraform apply
   ```

### Configuration Options

#### Basic Configuration (terraform.tfvars example)

```hcl
# Core settings
name_prefix  = "eksp-"
environment  = "dev"
aws_region   = "us-east-1"

# Knowledge Base settings
kb_name          = "agentic-kb"
embedding_model  = "amazon.nova-2-multimodal-embeddings-v1:0"
vector_dimension = 1024
distance_metric  = "cosine"

# KMS encryption (optional)
enable_kms_encryption = false
kms_key_arn           = null
```

#### Advanced Configuration

**Custom Embedding Model:**
```hcl
embedding_model  = "amazon.titan-embed-text-v2:0"
vector_dimension = 1024
```

**Different Distance Metric:**
```hcl
distance_metric = "euclidean"  # Options: cosine, euclidean, dot_product
```

**Enable KMS Encryption:**
```hcl
enable_kms_encryption = true
kms_key_arn           = "ARN HERE"
```

## Outputs

After deployment, Terraform outputs the following values:

- `knowledge_base_id` - Use this to query the KB directly
- `knowledge_base_arn` - ARN of the KB resource
- `vector_bucket_name` - S3 Vectors bucket name
- `parameter_store_name` - Parameter Store key with full configuration

View outputs:
```bash
terraform output
```

## Verification

### 1. Check Terraform Outputs
```bash
terraform output knowledge_base_id
```

### 2. Verify Parameter Store
```bash
aws ssm get-parameter \
  --name "/agentic-platform/config" \
  --region us-east-1 \
  --query 'Parameter.Value' \
  --output text | jq '.KNOWLEDGE_BASE_ID'
```

### 3. Check Kubernetes ConfigMap (requires kubectl configured)
```bash
kubectl get configmap agentic-platform-config -o yaml | grep KNOWLEDGE_BASE_ID
```

### 4. Test Knowledge Base Query
```bash
aws bedrock-agent-runtime retrieve \
  --knowledge-base-id $(terraform output -raw knowledge_base_id) \
  --retrieval-query text="test query" \
  --region us-east-1
```

## Updating

To update the knowledge base configuration:

1. Modify variables in `terraform.tfvars` or `variables.tf`
2. Run `terraform plan` to preview changes
3. Run `terraform apply` to apply changes
4. Restart affected pods to pick up new configuration:
   ```bash
   kubectl rollout restart deployment bedrock-kb-mcp-server
   ```

## Data Management

### Adding Documents to Knowledge Base

Upload documents to the S3 Vectors bucket:

```bash
# Get bucket name
BUCKET_NAME=$(terraform output -raw vector_bucket_name)

# Upload documents
aws s3 cp documents/ s3://$BUCKET_NAME/documents/ --recursive

# Sync/Index the knowledge base (triggers embedding)
aws bedrock-agent sync-knowledge-base \
  --knowledge-base-id $(terraform output -raw knowledge_base_id) \
  --region us-east-1
```

### Monitoring Sync Status

```bash
aws bedrock-agent get-knowledge-base \
  --knowledge-base-id $(terraform output -raw knowledge_base_id) \
  --region us-east-1 \
  --query 'knowledgeBase.status'
```

## Troubleshooting

### Knowledge Base Not Found

Check if the resource was created:
```bash
terraform state show module.knowledgebase.aws_bedrockagent_knowledge_base.kb
```

### Parameter Store Not Updating ConfigMap

The ConfigMap is managed by the platform-eks stack's Kubernetes module. Make sure:
1. The platform-eks stack has been deployed
2. The Kubernetes module is configured to read from Parameter Store
3. The ConfigMap controller is running

### Pod Not Getting KNOWLEDGE_BASE_ID

Check the deployment's envFrom configuration:
```bash
kubectl describe deployment bedrock-kb-mcp-server | grep -A 5 "Environment Variables from"
```

Should show:
```
Environment Variables from:
  agentic-platform-config  ConfigMap  Optional: false
```

## Cleanup

To destroy all resources:

```bash
terraform destroy
```

**Warning:** This will permanently delete:
- The Knowledge Base
- All S3 Vectors buckets and indices
- All indexed documents
- IAM roles and policies

Make sure to backup any important data first.

## Cost Considerations

- **S3 Vectors**: Storage costs for documents and indices
- **Bedrock Knowledge Base**: Pay per query and embedding generation
- **Parameter Store**: Standard tier is free for < 10,000 parameters
- **IAM**: No cost for roles and policies

Estimated monthly cost: $10-50 for light usage (depends on document volume and query frequency)

## Security

- IAM roles follow principle of least privilege
- Bedrock can only access designated S3 Vectors resources
- KMS encryption optional for S3 Vectors bucket
- Parameter Store values are not encrypted by default (add encryption if needed)

## Integration with Other Stacks

This stack is independent but integrates via:
- **Parameter Store**: Shares configuration with platform-eks
- **ConfigMap**: Platform-eks reads from Parameter Store
- **IAM**: Agent pods need `bedrock:Retrieve` permission (configured in platform-eks IRSA module)

## Region Availability

Ensure the Nova 2 multimodal embedding model is available in your region:
```bash
aws bedrock list-foundation-models \
  --region us-east-1 \
  --by-customization-type NONE \
  --query 'modelSummaries[?contains(modelId, `nova-2-multimodal-embeddings`)]'
```

If not available, use an alternative model:
- `amazon.titan-embed-text-v2:0` (1024 dimensions)
- `amazon.titan-embed-text-v1` (1536 dimensions)

Update `embedding_model` and `vector_dimension` variables accordingly.
