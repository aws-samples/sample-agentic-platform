# Bootstrap

**Note:** The bootstrap process is currently Work In Progress (WIP) following the Terraform refactor into modules. The infrastructure deployment process has been updated to use the new modular approach.

We've provided a series of bootstrap scripts and CloudFormation templates to get an entire CI/CD pipeline and infrastructure spun up. The bootstrap scripts should be run in this order:

1. **infra-bootstrap.yaml** - Infrastructure deployment
2. **github-bootstrap.yaml** - CI/CD pipeline setup (optional)
3. **LangFuse deployment** - Observability platform (optional)

# 1 Infrastructure Bootstrap

We've provided a bootstrap template written in CloudFormation to create the Terraform state management files and automatically deploy the infrastructure using a custom resource. We've chosen to bootstrap from CloudFormation for simplicity. CFN can be deployed locally or through the AWS CloudFormation console. Optionally, you can deploy the Terraform from your local machine or anywhere using the terraform plan && terraform apply. We recommend the bootstrap to persist TF state in the cloud.

### What is deployed

This stack deploys:
1. An S3 bucket to manage your Terraform state
2. An AWS CodeBuild project to deploy the sample agentic platform Terraform infrastructure
3. A Lambda acting as a custom resource that will lifecycle the Terraform deployment
4. (Optional) A KMS key

**Warning**: When this stack is torn down, the Terraform infrastructure will also be torn down.

### Getting Started

To get started, you can run this CloudFormation by (1) Deploying from your computer or (2) Deploy from the CloudFormation console.

#### Pre-Reqs

1. An AWS account
2. An IAM role (not user) you can use to give access to the Amazon EKS cluster and has access to your project KMS key
3. An IAM role (not user) for your CI/CD pipeline to deploy the Terraform via CodeBuild. This role must have a trust relationship with codebuild.amazonaws.com and appropriate permissions to deploy infrastructure

We've intentionally left out the CI/CD role creation in the bootstrap template to give flexibility to the implementor on how they want to configure that role. The role needs elevated privileges to deploy the Terraform infrastructure. You can use tools like AWS IAM Access Analyzer or projects like Role Vending Machine [here](https://github.com/aws-samples/role-vending-machine) to help you create a role with the appropriate permissions.

#### Deploying from computer

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

#### Deploying from the console

Navigate to the CloudFormation service in your AWS console. Create a new CloudFormation stack and upload bootstrap.yaml into the console to deploy. You will be prompted to add the correct role names for the FederatedRoleName and CICDRoleName parameters.

### Infrastructure Setup Complete

After ~20-30 minutes your infrastructure should be deployed!

# 2 GitHub Bootstrap (Optional)

In this section you'll:
* Sign in / up on github.com
* Create a new repository
* Import this repository into your own (private repo)
* Run a bootstrap script to create IAM permissions for GitHub to update containers in AWS
* Configure a repository secret & env variable for our CI pipeline
* Deploy containers to ECR

To begin, login or sign in to github.com

### Create and Fork repository

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

### Configure repository secrets

We'll need to configure our GitHub repository secrets so that our pipeline can deploy to ECR. We'll need to add:
* AWS_ROLE_ARN as a repository secret (which you should have from the GitHub bootstrap)
* AWS_REGION as an environment variable (whichever AWS region you deployed from)

Follow these instructions on how to find this in the GitHub website [here](https://docs.github.com/en/actions/security-for-github-actions/security-guides/using-secrets-in-github-actions)

### Deploy a change

Lastly, we need to trigger the code pipeline. Navigate to .github/workflows/ecr-push.yml and uncomment the on: section at the top and delete the one that's currently live. You can do this via the GitHub UI or via git commands. This will trigger your CI pipeline which will build your containers and push them to ECR repositories.

And that's it! We've completed the "CI" part of our "CI/CD" pipeline.

# 3 (Optional) Enable LangFuse

LangFuse is an open source LLM engineering platform that can be deployed in Kubernetes. For this sample, it also provides an additional location to send traces to demonstrate the power of using OpenTelemetry. Without changing your code, you can send your traces to any backend.

**Note:** If you are executing this script locally, make sure you're port forwarding through the bastion host like described in DEPLOYMENT.md. If you're already on the bastion host, you can run these directly.

To install LangFuse, run the following commands below:

```bash
# Make the script executable
chmod +x ./bootstrap/langfuse-bootstrap.sh 

# Deploy LangFuse via Helm
. ./bootstrap/langfuse-bootstrap.sh
```

# Conclusion

After following this README, you should have the stack deployed, GitHub setup (if you want CI/CD), and optionally LangFuse configured for enhanced observability. The infrastructure is now ready for deploying your agentic systems using the deployment scripts in the `/deploy` directory.
