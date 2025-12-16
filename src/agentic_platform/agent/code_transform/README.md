# ATX Container Test Runner

A containerized solution for running Amazon Transform eXtension (ATX) transformations at scale using AWS ECS, with automated CI/CD deployment via GitLab.

## 🎯 Overview

This project provides a complete infrastructure-as-code solution for deploying ATX transformations in a scalable, secure, and cost-effective manner. It orchestrates batch processing of code transformations stored in S3, executes them using ATX, and stores results back to S3.

## ✨ Key Features

- **🐳 Containerized ATX Runtime** - Consistent execution environment
- **📊 Batch Processing** - Process multiple repositories simultaneously  
- **🔄 GitLab CI/CD Integration** - Automated deployment and updates
- **🔐 OIDC Authentication** - Secure, keyless AWS access
- **📈 Auto-scaling** - ECS Fargate with configurable scaling
- **📝 Comprehensive Logging** - CloudWatch integration with detailed logs
- **💰 Cost Optimized** - Spot instances and pay-per-use pricing
- **🛡️ Security First** - Least privilege IAM, VPC isolation, encryption

## 🏗️ Architecture

```
┌─────────────────┐    ┌──────────────────┐    ┌─────────────────┐
│   GitLab CI/CD  │───▶│   Amazon ECR     │───▶│   Amazon ECS    │
│                 │    │  (Docker Images) │    │  (Fargate)      │
└─────────────────┘    └──────────────────┘    └─────────────────┘
                                                        │
┌─────────────────┐    ┌──────────────────┐           │
│   Amazon S3     │◀───│   ATX Container  │◀──────────┘
│ (Source & Results)   │  (Transformations)│
└─────────────────┘    └──────────────────┘
                                │
                       ┌──────────────────┐
                       │  CloudWatch Logs │
                       │   (Monitoring)   │
                       └──────────────────┘
```

## 🚀 Quick Start

### For Customers (Recommended)
See **[USER-GUIDE.md](USER-GUIDE.md)** for the complete customer deployment guide.

### For Developers
1. **Clone the repository**
   ```bash
   git clone <repository-url>
   cd atx-container-test-runner
   ```

2. **Set up AWS infrastructure**
   ```bash
   chmod +x setup-gitlab-ci.sh
   ./setup-gitlab-ci.sh
   ```

3. **Configure GitLab CI/CD**
   - See [GITLAB-DEPLOYMENT.md](GITLAB-DEPLOYMENT.md) for detailed setup

4. **Deploy**
   ```bash
   git push origin main
   ```

## 📚 Documentation

| Document | Purpose |
|----------|---------|
| **[USER-GUIDE.md](USER-GUIDE.md)** | 👥 Complete user deployment guide |
| **[GITLAB-DEPLOYMENT.md](GITLAB-DEPLOYMENT.md)** | 🔄 GitLab CI/CD setup and troubleshooting |
| **[QUICKSTART-ECS.md](QUICKSTART-ECS.md)** | ⚡ Quick ECS deployment guide |
| **[OIDC-SETUP-GUIDE.md](OIDC-SETUP-GUIDE.md)** | 🔐 OIDC authentication setup |
| **[QUICK-REFERENCE.md](QUICK-REFERENCE.md)** | 📖 Command reference and examples |
| **[docs/deployment-guide.md](docs/deployment-guide.md)** | 🏗️ Detailed deployment options |
| **[docs/troubleshooting.md](docs/troubleshooting.md)** | 🐛 Troubleshooting guide |
| **[docs/build-and-test.md](docs/build-and-test.md)** | 🧪 Build and test instructions |

## 🔧 Deployment Options

### 1. GitLab CI/CD (Recommended)
- **Automated deployment** on every push
- **OIDC authentication** for security
- **Built-in testing** and validation
- See [GITLAB-DEPLOYMENT.md](GITLAB-DEPLOYMENT.md)

### 2. CloudFormation
- **Infrastructure as Code** approach
- **Complete stack** deployment
- Uses `deployment/cloudformation-complete-stack.yaml`

### 3. Terraform
- **Multi-cloud** infrastructure management
- **State management** and planning
- Uses `deployment/terraform/`

### 4. Manual ECS Deployment
- **Step-by-step** manual process
- **Learning-focused** approach
- See [QUICKSTART-ECS.md](QUICKSTART-ECS.md)

## 📁 Repository Structure

```
atx-container-test-runner/
├── 📄 USER-GUIDE.md           # Customer deployment guide
├── 📄 GITLAB-DEPLOYMENT.md         # GitLab CI/CD setup guide  
├── 📄 QUICKSTART-ECS.md            # Quick ECS deployment
├── 📄 OIDC-SETUP-GUIDE.md          # OIDC authentication setup
├── 📄 QUICK-REFERENCE.md           # Command reference
├── 🔧 setup-gitlab-ci.sh           # Automated AWS setup
├── 🐳 Dockerfile                   # Container definition
├── ⚙️ .gitlab-ci.yml               # CI/CD pipeline
├── 📋 VERSION                      # Current version
│
├── 📂 docs/                        # Documentation
│   ├── deployment-guide.md         # Detailed deployment guide
│   ├── troubleshooting.md          # Troubleshooting help
│   ├── build-and-test.md           # Build and test guide
│   └── exit-codes-and-output-modes.md # Exit codes reference
│
├── 📂 scripts/                     # Orchestration scripts
│   ├── atx-orchestrator.sh         # Main orchestrator
│   ├── s3-integration.sh           # S3 operations
│   ├── csv-parser.sh               # CSV parsing utilities
│   ├── smoke-test.sh               # Container validation
│   └── push-to-ecr.sh              # ECR deployment
│
├── 📂 deployment/                  # Infrastructure templates
│   ├── cloudformation-complete-stack.yaml # Complete CF stack
│   ├── ecs-task-definition.json    # ECS task definition
│   ├── kubernetes-deployment.yaml  # Kubernetes manifests
│   └── terraform/                  # Terraform IaC
│       ├── main.tf                 # Main Terraform config
│       ├── variables.tf            # Variable definitions
│       └── outputs.tf              # Output definitions
│
├── 📂 examples/                    # Example configurations
│   ├── single-customer.csv         # Single customer example
│   ├── multi-customer.csv          # Multi-customer example
│   ├── sample-repos.csv            # Sample repositories
│   └── menu-folders.csv            # Menu structure example
│
└── 📂 spuragu-progress-to-ir/      # ATX transformation
    └── transformation_definition.md # Transformation specification
```

## 🔐 Security Features

- **🔑 OIDC Authentication** - No long-lived AWS access keys
- **🛡️ IAM Least Privilege** - Minimal required permissions
- **🔒 VPC Isolation** - Network security and isolation
- **🔐 Encryption at Rest** - S3 and ECR encryption
- **📊 Audit Logging** - CloudTrail and CloudWatch integration
- **🔍 Container Scanning** - ECR vulnerability scanning
- **🚫 Branch Protection** - OIDC limited to main branch

## 💰 Cost Optimization

- **💡 Spot Instances** - Up to 70% cost savings
- **📊 Auto-scaling** - Pay only for what you use
- **⏰ Scheduled Scaling** - Scale down during off-hours
- **🗂️ Lifecycle Policies** - Automatic log and image cleanup
- **📈 Cost Monitoring** - Built-in cost tracking and alerts

**Estimated Monthly Cost:** $35-70 (varies by usage)

## 🧪 Testing

```bash
# Run smoke tests
./scripts/smoke-test.sh

# Test container locally
docker build -t atx-test-runner .
docker run --rm atx-test-runner --smoke-test

# Run integration tests
./scripts/test-orchestrator.sh --csv-file examples/sample-repos.csv --dry-run
```

## 🔄 CI/CD Pipeline

The GitLab pipeline automatically:
1. ✅ **Validates** CloudFormation templates and scripts
2. 🐳 **Builds** Docker image with security scanning
3. 🧪 **Tests** functionality with smoke tests
4. 📦 **Pushes** to Amazon ECR with proper tagging
5. 🚀 **Deploys** to AWS ECS with health checks
6. ✔️ **Verifies** deployment success and functionality

## 📊 Monitoring and Logging

- **📈 CloudWatch Metrics** - ECS, ECR, and custom metrics
- **📝 Centralized Logging** - All logs in CloudWatch Logs
- **🚨 Alerting** - Automated alerts for failures and issues
- **📊 Dashboards** - Pre-built CloudWatch dashboards
- **🔍 Tracing** - Request tracing and performance monitoring

## 🤝 Contributing

1. Fork the repository
2. Create a feature branch (`git checkout -b feature/amazing-feature`)
3. Commit your changes (`git commit -m 'Add amazing feature'`)
4. Push to the branch (`git push origin feature/amazing-feature`)
5. Open a Pull Request

## 📄 License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

## 🆘 Support

- **📚 Documentation** - Check the `docs/` directory
- **🐛 Issues** - Report bugs via GitLab Issues
- **💬 Discussions** - Use GitLab Discussions for questions
- **📧 Contact** - Reach out to the development team

## 🎉 Getting Started

Ready to deploy? Start with **[USER-GUIDE.md](USER-GUIDE.md)** for the complete setup guide!

---

**Built with ❤️ for scalable ATX transformations**