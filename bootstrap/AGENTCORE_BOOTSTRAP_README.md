# AgentCore Platform Bootstrap
We've provided a series of bootstrap scripts and CloudFormation templates to get an entire CI/CD pipeline and infrastructure spun up. You can find detailed instructions on how to deploy below. 

# Instructions

## Step 1: Setup Infra CI/CD
We've provided a bootstrap template written in CloudFormation to create the Terraform state management files and set up a CodeBuild environment that can execute the terraform IAC. We've chosen to bootstrap from CloudFormation for simplicity. CFN can be deployed locally or through the AWS CloudFormation console. Optionally, you can deploy the Terraform from your local machine or anywhere using the terraform plan && terraform apply. We recommend the bootstrap to persist TF state in the cloud.

### What is deployed

This stack deploys:
1. An S3 bucket to manage your Terraform state
2. An AWS CodeBuild project to deploy the sample agentic platform Terraform infrastructure
3. A Lambda acting as a custom resource that will lifecycle the Terraform deployment

To get started, you can run this CloudFormation by (1) Deploying from your computer or (2) Deploy from the CloudFormation console.

#### Pre-Reqs

1. An AWS account
2. An IAM role (not user) you can use to give access to the Amazon EKS cluster and has access to your project KMS key
3. An IAM role (not user) for your CI/CD pipeline to deploy the Terraform via CodeBuild. **This role must have a trust relationship with codebuild.amazonaws.com and appropriate permissions to deploy infrastructure**

We've intentionally left out the CI/CD role creation in the bootstrap template to give flexibility to the implementor on how they want to configure that role. The role needs elevated privileges to deploy the Terraform infrastructure. You can use tools like AWS IAM Access Analyzer or projects like Role Vending Machine [here](https://github.com/aws-samples/role-vending-machine) to help you create a role with the appropriate permissions.

#### Deploying from computer

To deploy from your computer, run the following command in the sample-agentic-platform/bootstrap directory. Make sure to replace your FederatedRoleName parameter with the role you're using.

```bash
aws cloudformation create-stack \
  --stack-name agentptfm-bootstrap \
  --template-body file://agentcore-platform-bootstrap.yaml \
  --parameters \
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

#### Infrastructure Setup Complete

After ~20-30 minutes your infrastructure should be deployed!

## Step 2: Trigger Deployment
After the cloudformation stack is deployed, navigate to code build in that sam account and find the build project prefixed with agentcore-pltfm. Select the project and click **start build**. This will trigger the code build environment to deploy the terraform. When it says **succeeded** then the setup is complete.
