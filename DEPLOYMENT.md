# Deploy Sample Agent Platform

This guide covers deploying the sample agentic platform to AWS. The platform uses Terraform to create infrastructure and Kubernetes to deploy the applications.

**Important Notice:** This project deploys resources in your AWS environment using Terraform. You will incur costs for the AWS resources used. Please be aware of the pricing for services like EKS, Bedrock, OpenSearch, DynamoDB, Elasticache, S3, etc.

**Required Permissions:** You need elevated permissions to deploy the Terraform stack.

## Prerequisites

### Required Tools
- [Terraform using tfenv](https://github.com/tfutils/tfenv)
- [AWS CLI & configuration](https://docs.aws.amazon.com/cli/latest/userguide/getting-started-install.html)
- [SSM Plugin for AWS CLI](https://docs.aws.amazon.com/systems-manager/latest/userguide/session-manager-working-with-install-plugin.html) (for port forwarding)
- [uv](https://github.com/astral-sh/uv) for Python development
- [Docker](https://docs.docker.com/engine/install/)
- [kubectl](https://kubernetes.io/docs/tasks/tools/)

## Installation

Clone the repository:
```bash
git clone https://github.com/aws-samples/sample-agentic-platform.git
cd sample-agentic-platform
```

## Deployment Options

### Option 1: Automated Bootstrap (Recommended)

Use the automated bootstrap for production deployments. This approach deploys infrastructure from within the VPC for security and keeps the EKS cluster private.

**Note:** This option is currently Work In Progress (WIP).

```bash
# Follow the bootstrap deployment guide
cd bootstrap/
# See bootstrap/README.md for detailed instructions
```

### Option 2: Manual Deployment (Testing/Local Development)

For testing and development purposes, you can deploy the Terraform scripts directly.

#### 1. Infrastructure Deployment

Follow the detailed instructions in the [infrastructure README](infrastructure/README.md) for complete deployment steps including:
- Foundation stack (VPC setup)
- Platform-EKS stack (main infrastructure)
- PostgreSQL users setup

#### 2. Deploy LiteLLM

After completing the infrastructure setup, deploy LiteLLM:

```bash
./deploy/deploy-litellm.sh
```

#### 3. Deploy gateways

If you want to use the memory or retrieval gateways, run:

```bash
./deploy/deploy-gateways.sh --build
```

You can configure the memory gateway provider by modifying the `MEMORY_PROVIDER` setting in the `configDefaults` section of `k8s/helm/values/applications/memory-gateway-values.yaml`.

#### 4. Deploy Applications

To deploy an agent application:

```bash
# Deploy a specific application (replace <dockerfile-name> with actual name)
./deploy/deploy-application.sh <dockerfile-name> --build

# Examples:
./deploy/deploy-application.sh agentic-chat --build
./deploy/deploy-application.sh langgraph-chat --build
```

## Accessing the Private EKS Cluster

Since the EKS cluster is private (when deployed via bootstrap), you need to access it through the bastion host using SSM port forwarding. **Note:** You'll need the AWS SSM plugin installed for port forwarding to work.

1. **Find your bastion instance ID:**
```bash
INSTANCE_ID=$(aws ec2 describe-instances \
  --filters "Name=tag:Name,Values=*bastion-instance*" "Name=instance-state-name,Values=running" \
  --query "Reservations[].Instances[].InstanceId" \
  --output text)
```

2. **Start port forwarding to kubectl proxy:**
```bash
aws ssm start-session \
  --target $INSTANCE_ID \
  --document-name AWS-StartPortForwardingSession \
  --parameters '{"portNumber":["8080"],"localPortNumber":["8080"]}'
```

3. **Configure kubectl (in a new terminal):**
```bash
kubectl config set-cluster eks-proxy --server=http://localhost:8080
kubectl config set-credentials eks-proxy-user
kubectl config set-context eks-proxy --cluster=eks-proxy --user=eks-proxy-user
kubectl config use-context eks-proxy
```

4. **Verify access:**
```bash
kubectl get nodes
```

### Alternative: Using Code Server on Bastion Host

If you prefer not to set up local kubectl configuration, you can use the code server that's installed on the bastion host. This approach makes it easier to work with all the private resources since you're operating directly from within the VPC.

**Access Code Server:**
```bash
# Port forward to code server on the bastion host
aws ssm start-session \
  --target $INSTANCE_ID \
  --document-name AWS-StartPortForwardingSession \
  --parameters '{"portNumber":["8888"],"localPortNumber":["8888"]}'
```

Then open `http://localhost:8888` in your web browser to access the code server running on the bastion host. From there, you can run all deployment commands, access kubectl directly, and work with the labs without needing local setup.

## Database Setup

### Running Database Migrations

After the infrastructure is deployed and you have kubectl access configured (either locally or via code server), run the database migrations:

```bash
./deploy/run-migrations.sh
```

This script automatically:
- Finds the bastion instance and database cluster
- Retrieves credentials from AWS Secrets Manager
- Sets up port forwarding through the bastion
- Runs Alembic migrations
- Cleans up automatically

## Public Access with CloudFront

By default, the load balancer ingress rules are configured to be private. If you'd like to expose endpoints publicly and enable HTTPS, you can configure the cloudfront distruvtion to use the load balancer as a VPC origin once you've deployed a resource with ingress (which will automatically create an ALB)

AWS recently introduced [CloudFront VPC Origins](https://aws.amazon.com/blogs/networking-and-content-delivery/introducing-cloudfront-virtual-private-cloud-vpc-origins-shield-your-web-applications-from-public-internet/), which allows you to securely deliver content from applications hosted in private subnets without exposing them to the public internet. This approach allows you to enable https using CloudFront's cert if you don't have one available.

## Testing the Deployment

### Create Test User and Generate Token

```bash
# Create test user
uv run python script/create_test_user.py --user-pool-id <from_tf_output> --email <email> --password "password"

# Generate auth token
uv run python script/get_auth_token.py --username 'user' --password 'password' --client-id <from_tf_output>
```

### Test API Endpoints

You can test the deployed services either through the load balancer (internet-facing) or via local port forwarding:

```bash
# Port forward to a specific service
kubectl port-forward svc/langgraph-chat 8090:80

# Test the chat endpoint
curl -X POST http://localhost:8090/chat \
  -H "Authorization: Bearer <token>" \
  -H "Content-Type: application/json" \
  -d '{"message": "hello"}'
```

## Running Code Locally

For local development, use the provided Docker Compose setup:

```bash
# Start local dependencies
docker compose up

# Run specific services
make agentic-chat
```

## Observability

The platform includes comprehensive observability:
- **Traces**: AWS X-Ray or LangFuse
- **Metrics**: CloudWatch  
- **Logs**: OpenSearch

OpenTelemetry collectors are deployed via the bootstrap scripts and configured to send telemetry data to these AWS services.

## Teardown

To clean up resources:

1. **Remove Kubernetes resources:**
```bash
helm uninstall lb-controller
```

2. **Remove deletion protection from Aurora:**
```bash
terraform apply -auto-approve -var="postgres_deletion_protection=false" -target=aws_rds_cluster.postgres
```

3. **Destroy infrastructure:**
```bash
terraform destroy
```

## Troubleshooting

- **Database connection issues**: Ensure migrations have been run using `./deploy/run-migrations.sh`
- **Pod access issues**: Verify kubectl is configured with port forwarding to the bastion host
- **Permission issues**: Verify your IAM role has sufficient permissions for EKS and other AWS services

For more detailed troubleshooting, see the individual README files in the `bootstrap/`, `deploy/`, and `labs/` directories.
