# Bootstrap

**Note:** The bootstrap process is currently Work In Progress (WIP) following the Terraform refactor into modules. The infrastructure deployment process has been updated to use the new modular approach.

We've provided a series of bootstrap scripts and CloudFormation templates to get an entire CI/CD pipeline and infrastructure spun up. The bootstrap scripts should be run in this order:

1. **infra-bootstrap.yaml** - Infrastructure deployment
2. **github-bootstrap.yaml** - CI/CD pipeline setup (optional)
3. **LangFuse deployment** - Observability platform (optional)

## 1. Infrastructure Bootstrap

We've provided a bootstrap template written in CloudFormation to create the Terraform state management files and automatically deploy the infrastructure using a custom resource. We've chosen to bootstrap from CloudFormation for simplicity. CFN can be deployed locally or through the AWS CloudFormation console. Optionally, you can deploy the Terraform from your local machine or anywhere using the terraform plan && terraform apply. We recommend the bootstrap to persist TF state in the cloud.

### What is Deployed

This stack deploys:
1. An S3 bucket to manage your Terraform state
2. An AWS CodeBuild project to deploy the sample agentic platform Terraform infrastructure
3. A Lambda acting as a custom resource that will lifecycle the Terraform deployment
4. (Optional) A KMS key

**Warning**: When this stack is torn down, the Terraform infrastructure will also be torn down.

### Getting Started

To get started, you can run this CloudFormation by (1) Deploying from your computer or (2) Deploy from the CloudFormation console.

#### Prerequisites

1. An AWS account
2. An IAM role (not user) you can use to give access to the Amazon EKS cluster and has access to your project KMS key
3. An IAM role (not user) for your CI/CD pipeline to deploy the Terraform via CodeBuild. This role must have a trust relationship with codebuild.amazonaws.com and appropriate permissions to deploy infrastructure

We've intentionally left out the CI/CD role creation in the bootstrap template to give flexibility to the implementor on how they want to configure that role. The role needs elevated privileges to deploy the Terraform infrastructure. You can use tools like AWS IAM Access Analyzer or projects like Role Vending Machine [here](https://github.com/aws-samples/role-vending-machine) to help you create a role with the appropriate permissions.

**Note:** There are 2 sample CloudFormation scripts provided in this bootstrap folder as examples:
- `agentptfm-cicd-role.yaml` - Creates a CI/CD role for CodeBuild
- `agentptfm-federated-role.yaml` - Creates a federated role for EKS access

These templates can be used after you review them and determine they meet your security requirements. They provide a starting point for the required IAM roles but should be customized based on your organization's security policies and least-privilege principles.

**Security Warning:** These sample roles include broad permissions necessary for infrastructure deployment. Review and restrict permissions according to your security requirements before using in production environments. IF YOU HAVE COMPLED THE REVIEW YOU CAN:
```bash
#Create the federated role for EKS
aws cloudformation create-stack \
  --stack-name agentptfm-federated-role \
  --template-body file://agentptfm-federated-role.yaml \
  --capabilities CAPABILITY_NAMED_IAM
```
```bash
#Create the CICD role
aws cloudformation create-stack \
  --stack-name agentptfm-cicd-role \
  --template-body file://agentptfm-cicd-role.yaml \
  --capabilities CAPABILITY_NAMED_IAM
```


#### Deploying from Computer

To deploy from your computer, run the following command in the sample-agentic-platform/bootstrap directory. Make sure to replace your FederatedRoleName parameter with the role you're using.

```bash
aws cloudformation create-stack \
  --stack-name agentptfm-bootstrap \
  --template-body file://infra-bootstrap.yaml \
  --parameters \
    ParameterKey=FederatedRoleName,ParameterValue=<YOUR ROLE NAME> \
    ParameterKey=CICDRoleName,ParameterValue=<YOUR CICD ROLE NAME> \
  --capabilities CAPABILITY_NAMED_IAM
```

> **Note**: The CI/CD role must have a trust relationship with the CodeBuild service. Make sure the role has the following trust policy:
> ```json
> {
>   "Version": "2012-10-17",
>   "Statement": [
>     {
>       "Effect": "Allow",
>       "Principal": {
>         "Service": "codebuild.amazonaws.com"
>       },
>       "Action": "sts:AssumeRole"
>     }
>   ]
> }
> ```

#### Deploying from the Console

Navigate to the CloudFormation service in your AWS console. Create a new CloudFormation stack and upload bootstrap.yaml into the console to deploy. You will be prompted to add the correct role names for the FederatedRoleName and CICDRoleName parameters.

### Infrastructure Setup Complete

After ~20-30 minutes your infrastructure should be deployed!

## 2. GitHub Bootstrap (Optional)

In this section you'll:

- Sign in / up on github.com
- Create a new repository
- Import this repository into your own (private repo)
- Run a bootstrap script to create IAM permissions for GitHub to update containers in AWS
- Configure a repository secret & env variable for our CI pipeline
- Deploy containers to ECR

To begin, login or sign in to github.com

### Create and Fork Repository

Next, you'll need to fork this repository to your own GitHub account. Navigate to the main repository page and click the "Fork" button in the top-right corner. Follow the fork creation instructions [here](https://docs.github.com/en/pull-requests/collaborating-with-pull-requests/working-with-forks/fork-a-repo). 

**Recommendation:** Make your forked repository private for security purposes, especially since you'll be adding AWS credentials and configuration.

### Run GitHub Bootstrap

We'll be using GitHub Actions as our CI pipeline. GitHub will need permissions to deploy our containers to Elastic Container Registry (ECR). To do this, we've provided another CloudFormation template to set up those permissions.

Similar to the infrastructure setup CFN template, you can either run it in the AWS console or locally. To run locally use this command:

```bash
aws cloudformation create-stack \
  --stack-name github-bootstrap \
  --template-body file://bootstrap.yaml \
  --parameters \
    ParameterKey=GitHubOrg,ParameterValue=< YOUR ORG or YOUR PERSONAL GITHUB USER ID > \
    ParameterKey=GitHubRepo,ParameterValue=<NAME OF THE REPO YOU JUST CREATED> \
  --capabilities CAPABILITY_NAMED_IAM
```

When the script is done, you should have a GitHub role ARN that we'll use to finish up setup.

### Configure Repository Secrets

We'll need to configure our GitHub repository secrets so that our pipeline can deploy to ECR. We'll need to add:

- AWS_ROLE_ARN as a repository secret (which you should have from the GitHub bootstrap)
- AWS_REGION as an environment variable (whichever AWS region you deployed from)

Follow these instructions on how to find this in the GitHub website [here](https://docs.github.com/en/actions/security-for-github-actions/security-guides/using-secrets-in-github-actions)

### Deploy a Change

Lastly, we need to trigger the code pipeline. Navigate to .github/workflows/ecr-push.yml and uncomment the on: section at the top and delete the one that's currently live. You can do this via the GitHub UI or via git commands. This will trigger your CI pipeline which will build your containers and push them to ECR repositories.

And that's it! We've completed the "CI" part of our "CI/CD" pipeline.

## 3. Configure EKS Access Roles

After the bootstrap stack is deployed, you need to configure additional admin roles for EKS access:

1. **Get your current IAM principal:**
   ```bash
   aws sts get-caller-identity
   ```
   
   Example output:
   ```
   "arn:aws:sts::123456789012:assumed-role/admin/username-session"
   ```

2. **Convert assumed role to role ARN:** If you get an assumed role ARN (contains assumed-role), you must convert it to the base role ARN by removing the session part:

   From: `arn:aws:sts::123456789012:assumed-role/admin/username-session`
   To: `arn:aws:iam::123456789012:role/admin`

3. **Update CodeBuild configuration:** Navigate to the AWS CodeBuild console and update your project's environment variables or Terraform configuration:

   Find this line in your Terraform configuration:
   ```terraform
   # additional_admin_role_arns = ["<ARN for your AgenticPlatformCICDRole>","<YOUR_IAM_PRINCIPAL_ARN>"]
   ```
   
   Uncomment and replace with your actual ARNs:
   ```terraform
   additional_admin_role_arns = [
     "arn:aws:iam::123456789012:role/AgenticPlatformCICDRole",
     "arn:aws:iam::123456789012:role/admin"
   ]
   ```
   
   Where:
   - First ARN: Your AgenticPlatformCICDRole created by the CloudFormation stack
   - Second ARN: Your IAM principal role ARN from step 2

**Important:** This configuration is required for proper EKS cluster access. Without it, you may encounter permission issues when deploying applications.

3.1 **Continued CodeBuild configuration:** (optional if you have forked your ownn giuthub repo)
    Within the CodeBuild UI for your build, after clicking into edit, find and expand the "Additional configuration" section
    Scroll down and find the "Environment Variables"
    Edit the value for "REPO_URL" to be your forked repo for example:
      CURRENT VALUE:https://github.com/aws-samples/sample-agentic-platform
      YOUR VALUE:  https://github.com/< YOUR ORG or YOUR PERSONAL GITHUB USER ID >/< NAME OF THE REPO YOU JUST CREATED >
    Note: You do not need the ".git" at the end of the URL
    Edit the value for "TF_PATH" to be your path for example:
      CURRENT VALUE: sample-agentic-platform/infrastructure/stacks/platform-eks
      YOU VALUE: < NAME OF THE REPO YOU JUST CREATED >/infrastructure/stacks/platform-eks
      

## 4. Test the Deployment Manually

After updating the configuration, manually trigger the CodeBuild project from the AWS console to verify everything works correctly:

- Navigate to AWS CodeBuild in the console
- Find your `agentptfm-bootstrap` project
- Click "Start build"
- Monitor the build logs to ensure successful deployment

**Important:** Verify that both APPLY and DESTROY operations work correctly:
- First run should APPLY the infrastructure
- Test a DESTROY operation to ensure cleanup works
- Run APPLY again to redeploy for actual use

This validation step is crucial before proceeding with the rest of the deployment process.

## 5. Configure Kubectl Access to Private EKS Cluster

Since the EKS cluster is deployed privately, you need to access it through the bastion host using SSM port forwarding:

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

**Note:** Keep the SSM session running in the background while working with kubectl. If you close the session, you'll need to restart the port forwarding to regain cluster access.

**Alternative:** You can also use the code server installed on the bastion host by port forwarding to port 8888 and accessing http://localhost:8888 in your browser for a complete development environment within the VPC.



## 6. PostgreSQL Users Setup

After the platform stack is deployed, you need to create PostgreSQL users, databases, and permissions using the `postgres-users` stack. This is a **one-time setup**.

### Option A: Running from Local Machine (Port Forwarding Required)

If running from your local machine, you need to port forward through the bastion host:

```bash
# Get the bastion instance ID
INSTANCE_ID=$(aws ec2 describe-instances \
  --filters "Name=tag:Name,Values=*bastion-instance*" "Name=instance-state-name,Values=running" \
  --query "Reservations[].Instances[].InstanceId" \
  --output text)

# Get the Aurora writer endpoint, AURORA_ENDPOINT can be found in your codebuild build logs under "postgres_cluster_endpoint"
# Replace <your_postgres_cluster_endpoint> with your value
cd infrastructure/stacks/platform-eks/
export AURORA_ENDPOINT="<your_postgres_cluster_endpoint>"

# Start port forwarding session
aws ssm start-session \
  --target $INSTANCE_ID \
  --document-name AWS-StartPortForwardingSessionToRemoteHost \
  --parameters "portNumber=5432,localPortNumber=5432,host=$AURORA_ENDPOINT"

# In a new terminal, run the postgres-users stack with local proxy enabled
cd infrastructure/stacks/postgres-users/
terraform init
terraform apply -var="use_local_proxy=true"
```

### Option B: Running from Bastion Host

If running directly from the bastion host, you can execute terraform directly:

```bash
# Access bastion host via code server (port 8888) or SSM session, then:
cd infrastructure/stacks/postgres-users/
terraform init
terraform apply  # use_local_proxy defaults to false
```

### Getting the Aurora Writer Endpoint

You can get the Aurora writer endpoint from the platform-eks stack outputs:
**Note:** This `postgres_cluster_endpoint` value is also available from the CodeBuild logs in the AWS console.

```bash
cd infrastructure/stacks/platform-eks/
terraform output postgres_cluster_endpoint
```


### Deploy Core Services

After completing the infrastructure setup and PostgreSQL configuration, deploy the core platform services:

#### Deploy LiteLLM

Deploy the LiteLLM gateway for LLM model management from the root directory:

```bash
./deploy/deploy-litellm.sh
kubectl get configmap litellm-config
kubectl get secret litellm-secret
kubectl get externalsecrets
kubectl get pods #ensure its running, if not then you should NOT proceed beyond this point.
# if not running you can take a look at the pod:
# kubectl logs -f <pod_name>
```

#### Deploy Gateways (Optional)

If you want to use the memory or retrieval gateways, run:

```bash
./deploy/deploy-gateways.sh --build
kubectl get configmap memory-gateway-config
kubectl get configmap retrieval-gateway-config
kubectl get secret memory-gateway-agent-secret
kubectl get secret retrieval-gateway-agent-secret
kubectl get externalsecrets
kubectl get pods
```


```bash
# Test them
kubectl port-forward svc/memory-gateway 8091:80
kubectl port-forward svc/retrieval-gateway 8092:80

# Test endpoints (check their server.py files for exact paths)
curl http://localhost:8091/api/memory-gateway/health
curl http://localhost:8092/api/retrieval-gateway/health
```

**Note:** The --build flag will build the Docker images. If you're running this locally and encounter Docker issues, you can omit the flag to use pre-built images.


## 7. (Optional) Enable LangFuse

LangFuse is an open source LLM engineering platform that can be deployed in Kubernetes. For this sample, it also provides an additional location to send traces to demonstrate the power of using OpenTelemetry. Without changing your code, you can send your traces to any backend.

**Note:** If you are executing this script locally, make sure you're port forwarding through the bastion host like described in DEPLOYMENT.md. If you're already on the bastion host, you can run these directly.

To install LangFuse, run the following commands below:

```bash
# Make the script executable
chmod +x ./bootstrap/langfuse-bootstrap.sh 

# Deploy LangFuse via Helm
. ./bootstrap/langfuse-bootstrap.sh
```

**Note:** Tearing down/removal of Langfuse can be achieved by passing the --cleanup flag to the langfuse-bootstrap.sh script. If during cleanup the script seems to hang on namesapce deletion you may have finalizers that need manual adjustment. The following is an example only, your commands will differ:
```bash
# kubectl get namespace langfuse -o yaml | grep -A 10 finalizers
# kubectl patch ingress langfuse -n langfuse -p '{"metadata":{"finalizers":null}}' --type=merge
```


## 8. Deploy Applications

Now deploy some apps:

```bash
# Deploy an application (without --build first to avoid Docker issues)
./deploy/deploy-application.sh langgraph-chat

# If that works, then try with --build after fixing Docker
./deploy/deploy-application.sh langgraph-chat --build

# Then agentic-chat
./deploy/deploy-application.sh agentic-chat --build
```

## 9. Database Migrations

### Running Database Migrations

After the infrastructure is deployed and you have kubectl access configured (either locally or via code server), run the database migrations:

```bash
uv run ./deploy/run-migrations.sh
```

## 10. Testing the Deployment

### Create Test User and Generate Token
USER_POOL_ID can be found in the codebuild logs under: "cognito_user_pool_id"
CLIENT_ID can be found in the codebuild logs under: "cognito_web_client_id"

```bash
# Create test user
uv run python script/create_test_user.py --user-pool-id "[USER_POOL_ID]" --email "[email]" --password "[password]"

# Generate auth token
uv run python script/get_auth_token.py --username '[email]' --password '[password]' --client-id "[CLIENT_ID]"
```

Save that bearer token value (we'll use it in our tests).

### Test the Applications

```bash
# Port forward to a specific service
kubectl port-forward svc/[SERVICE_NAME] 8090:80
export YOUR_TOKEN=<the value of the bearer token from above>
# Test langgraph-chat app
curl -X POST http://localhost:8090/chat \
-H "Authorization: Bearer $YOUR_TOKEN" \
-H "Content-Type: application/json" \
-d '{
  "message": {
    "role": "user",
    "content": [
      {
        "type": "text",
        "text": "Hello, I just successfully deployed my langgraph-chat agent on AWS!"
      }
    ]
  }
}'


# Test agentic-chat app
kubectl port-forward svc/agentic-chat 8099:80
curl -X POST http://localhost:8099/api/agentic-chat/invoke \
-H "Authorization: Bearer $YOUR_TOKEN" \
-H "Content-Type: application/json" \
-d '{"message": {"role": "user","content": [{"type": "text", "text": "Hello, I just successfully deployed my agentic-chat agent on AWS!"}]},"session_id": "test-session-123"}'
```

# Conclusion

After following this README, you should have the stack deployed, GitHub setup (if you want CI/CD), and optionally LangFuse configured for enhanced observability. The infrastructure is now ready for deploying your agentic systems. You can optionally use the deployment scripts in the `/deploy` directory for additional application deployments.
