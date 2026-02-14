# ATX Container Test Runner - Customer Package

Welcome! This package contains everything you need to deploy the ATX Container Test Runner to your AWS account using GitLab CI/CD.

## 📦 What's Included

```
atx-container-test-runner/
├── USER-GUIDE.md              ← Start here!
├── README.md                       ← Project overview
├── GITLAB-DEPLOYMENT.md            ← Complete GitLab setup guide
├── QUICKSTART-ECS.md               ← Quick start for ECS deployment
├── OIDC-SETUP-GUIDE.md             ← OIDC authentication setup
├── QUICK-REFERENCE.md              ← Quick reference guide
├── setup-gitlab-ci.sh              ← Automated setup script
├── .gitlab-ci.yml                  ← GitLab CI/CD pipeline
├── Dockerfile                      ← Container definition
├── VERSION                         ← Current version
├── LICENSE                         ← License information
├── MANIFEST.txt                    ← Package manifest
├── gitlab-ci-policy.json           ← GitLab CI policy configuration
│
├── docs/                           ← Documentation
│   ├── deployment-guide.md         ← Detailed deployment guide
│   ├── troubleshooting.md          ← Troubleshooting help
│   ├── build-and-test.md           ← Build and test instructions
│   └── exit-codes-and-output-modes.md ← Exit codes reference
│
├── scripts/                        ← Orchestration scripts
│   ├── atx-orchestrator.sh         ← Main orchestrator
│   ├── s3-integration.sh           ← S3 operations
│   ├── csv-parser.sh               ← CSV parsing utilities
│   ├── smoke-test.sh               ← Container validation
│   ├── push-to-ecr.sh              ← ECR push automation
│   ├── entrypoint.sh               ← Container entrypoint
│   └── test-orchestrator.sh        ← Test orchestration
│
├── deployment/                     ← Deployment templates
│   ├── cloudformation-complete-stack.yaml  ← Complete infrastructure
│   ├── ecs-task-definition.json    ← ECS task definition
│   ├── kubernetes-deployment.yaml  ← Kubernetes manifests
│   └── terraform/                  ← Terraform IaC
│       ├── main.tf                 ← Main Terraform config
│       ├── variables.tf            ← Variable definitions
│       ├── outputs.tf              ← Output definitions
│       └── terraform.tfvars.example ← Example variables
│
├── examples/                       ← Example configurations
│   ├── single-customer.csv         ← Single customer example
│   ├── multi-customer.csv          ← Multi-customer example
│   ├── sample-repos.csv            ← Sample repositories
│   ├── menu-folders.csv            ← Menu structure example
│   ├── nested-structure.csv        ← Nested folder example
│   ├── different-transformations.csv ← Multiple transformations
│   ├── ci-cd-integration.sh        ← CI/CD integration example
│   └── kubernetes-job.yaml         ← Kubernetes job example
│
└── spuragu-progress-to-ir/         ← ATX transformation definition
    ├── transformation_definition.md ← Transformation specification
    └── document_references/         ← Supporting documentation
```

## 🚀 Quick Start (3 Steps)

### Step 1: Run Setup Script

```bash
# Make the script executable
chmod +x setup-gitlab-ci.sh

# Run the setup (creates AWS resources and IAM credentials)
./setup-gitlab-ci.sh
```

This script will:
- Create S3 buckets for source code and results
- Set up OIDC Identity Provider for GitLab
- Create IAM role with secure temporary credentials
- Display configuration values

**Benefits of OIDC:**
- ✅ No long-lived access keys to manage
- ✅ Automatic credential rotation
- ✅ Enhanced security with temporary tokens
- ✅ Better compliance and auditing

### Step 2: Configure GitLab

1. **Push this repository to your GitLab account:**
   ```bash
   git init
   git add .
   git commit -m "Initial commit"
   git remote add origin https://gitlab.com/your-username/atx-container-test-runner.git
   git push -u origin main
   ```

2. **In GitLab, go to Settings → CI/CD → Variables**

3. **Add the variables displayed by the setup script:**
   - `AWS_REGION`
   - `AWS_ACCOUNT_ID`
   - `AWS_ROLE_ARN`
   - `SOURCE_BUCKET`
   - `RESULTS_BUCKET`

   **Note:** No access keys needed! OIDC provides secure, temporary credentials automatically.

### Step 3: Deploy

```bash
# Push to trigger the pipeline
git commit --allow-empty -m "Trigger deployment"
git push origin main
```

The GitLab pipeline will automatically:
1. ✅ Validate CloudFormation templates
2. 🐳 Build Docker image
3. 🧪 Run smoke tests
4. 📦 Push to Amazon ECR
5. 🚀 Deploy to AWS ECS
6. ✔️ Verify deployment

## 📖 Documentation

- **[README.md](README.md)** - Project overview and developer guide
- **[GITLAB-DEPLOYMENT.md](GITLAB-DEPLOYMENT.md)** - Complete GitLab CI/CD setup guide
- **[QUICKSTART-ECS.md](QUICKSTART-ECS.md)** - Quick start for ECS deployment
- **[OIDC-SETUP-GUIDE.md](OIDC-SETUP-GUIDE.md)** - OIDC authentication setup
- **[QUICK-REFERENCE.md](QUICK-REFERENCE.md)** - Quick reference and commands
- **[docs/deployment-guide.md](docs/deployment-guide.md)** - Detailed deployment guide
- **[docs/troubleshooting.md](docs/troubleshooting.md)** - Troubleshooting help
- **[docs/build-and-test.md](docs/build-and-test.md)** - Build and test instructions
- **[docs/exit-codes-and-output-modes.md](docs/exit-codes-and-output-modes.md)** - Exit codes reference

## 🔧 Deployment Options

This package supports multiple deployment methods:

### 1. GitLab CI/CD (Recommended)
- Automated deployment on every push
- Uses `.gitlab-ci.yml` pipeline
- See `GITLAB-DEPLOYMENT.md`

### 2. CloudFormation
- Complete infrastructure as code
- Uses `deployment/cloudformation-complete-stack.yaml`
- See `docs/deployment-guide.md`

### 3. Terraform
- Infrastructure as code with Terraform
- Uses `deployment/terraform/`
- See `deployment/terraform/terraform.tfvars.example`

### 4. Manual Deployment
- Step-by-step manual deployment
- See `QUICKSTART-ECS.md`

## 🏗️ Architecture

The solution deploys:
- **ECS Fargate Cluster** - Serverless container orchestration
- **ECR Repository** - Docker image storage
- **VPC & Networking** - Isolated network environment
- **IAM Roles** - Secure access to AWS services
- **CloudWatch Logs** - Centralized logging
- **S3 Buckets** - Source code and results storage

## 💰 Cost Estimate

Typical monthly costs (us-east-1):
- ECS Fargate: ~$30-50/month (with Spot instances)
- ECR Storage: ~$1-5/month
- S3 Storage: ~$1-10/month
- CloudWatch Logs: ~$1-5/month
- **Total: ~$35-70/month**

Costs vary based on:
- Number of transformations
- Code repository sizes
- Log retention
- Task execution time

## 🔒 Security

This package follows AWS security best practices:
- ✅ **OIDC authentication** - No long-lived access keys
- ✅ **Temporary credentials** - Auto-rotating tokens (1 hour)
- ✅ **IAM roles with least privilege** - Minimal required permissions
- ✅ **ECR image scanning** - Vulnerability detection
- ✅ **Encryption at rest** - S3 and ECR encrypted
- ✅ **VPC isolation** - Network security
- ✅ **CloudWatch Logs** - Complete audit trail
- ✅ **Branch restrictions** - OIDC limited to main branch

## 🆘 Support

### Common Issues

1. **Pipeline fails at build stage**
   - Ensure Docker executor is available in GitLab Runner
   - Check Dockerfile syntax

2. **Pipeline fails at push stage**
   - Verify AWS credentials in GitLab variables
   - Check IAM permissions for ECR

3. **Pipeline fails at deploy stage**
   - Verify S3 buckets exist
   - Check CloudFormation events in AWS Console

4. **Task fails to run**
   - Check CloudWatch Logs: `/ecs/production-atx-test-runner`
   - Verify IAM task role has S3 permissions

See **[docs/troubleshooting.md](docs/troubleshooting.md)** for detailed solutions.

## 📞 Getting Help

1. Check the documentation in `docs/`
2. Review `GITLAB-DEPLOYMENT.md` for GitLab-specific issues
3. Check AWS CloudWatch Logs for runtime errors
4. Review GitLab pipeline logs for CI/CD issues

## 🔄 Updates

To update to a new version:

```bash
# Pull latest changes
git pull origin main

# Push to trigger redeployment
git push gitlab main
```

The pipeline will automatically rebuild and redeploy.

## 🧹 Cleanup

To remove all AWS resources:

1. In GitLab, go to **CI/CD → Pipelines**
2. Find the latest pipeline
3. Click the **destroy:stack** manual job
4. Click **Play** to execute

Or manually:
```bash
aws cloudformation delete-stack --stack-name atx-test-runner --region us-east-1
```

## 📝 License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

## 🎉 You're Ready!

Run `./setup-gitlab-ci.sh` to get started!
