# ATX Container Test Runner - Quick Reference

## Setup Method

**Shell Script Setup:**

```bash
# 1. Run OIDC setup script
chmod +x setup-gitlab-ci.sh
./setup-gitlab-ci.sh

# 2. Provide GitLab project ID when prompted

# 3. Push to GitLab
git push origin main

# 4. Add OIDC variables to GitLab Variables
# Settings → CI/CD → Variables
# (No access keys needed!)

# 5. Pipeline runs automatically with secure OIDC
```

## Required GitLab Variables (OIDC)

| Variable | Example | Protected | Masked |
|----------|---------|-----------|--------|
| `AWS_REGION` | `us-east-1` | | |
| `AWS_ACCOUNT_ID` | `123456789012` | | |
| `AWS_ROLE_ARN` | `arn:aws:iam::123456789012:role/GitLabCIRole` | | |
| `SOURCE_BUCKET` | `atx-test-source-...` | | |
| `RESULTS_BUCKET` | `atx-test-results-...` | | |

**✅ No access keys needed! OIDC provides secure, temporary credentials.**

## Pipeline Stages

### Main Pipeline (`.gitlab-ci.yml`)

1. **validate** - Validate CloudFormation
2. **build** - Build Docker image
3. **test** - Run smoke tests
4. **push** - Push to ECR (main branch only)
5. **deploy** - Deploy to ECS (main branch only)
6. **verify** - Verify deployment

## Common Commands

### Check Pipeline Status
```bash
# View in GitLab
# CI/CD → Pipelines
```

### Run Manual Jobs
```bash
# In GitLab pipeline view:
# Click ▶ (Play) button next to job name
```

### View Logs
```bash
# CloudWatch Logs
aws logs tail /ecs/production-atx-test-runner --follow

# Or in AWS Console:
# CloudWatch → Log groups → /ecs/production-atx-test-runner
```

### Run Test Task
```bash
# Use manual job in pipeline: run:test-task
# Or via AWS CLI:
aws ecs run-task \
  --cluster production-atx-cluster \
  --task-definition production-atx-test-runner \
  --launch-type FARGATE \
  --network-configuration "awsvpcConfiguration={subnets=[subnet-xxx],securityGroups=[sg-xxx],assignPublicIp=ENABLED}"
```

### Destroy Stack
```bash
# Use manual job in pipeline: destroy:stack
# Or via AWS CLI:
aws cloudformation delete-stack --stack-name atx-test-runner
```

## Troubleshooting

### Pipeline Fails at Build
- Check Dockerfile syntax
- Ensure Docker executor available

### Pipeline Fails at Push
- Verify AWS credentials in GitLab
- Check IAM permissions for ECR

### Pipeline Fails at Deploy
- Verify S3 buckets exist
- Check CloudFormation events in AWS Console

### Task Fails to Run
- Check CloudWatch Logs
- Verify IAM task role has S3 permissions

## File Structure

```
atx-container-test-runner/
├── .gitlab-ci.yml              ← Main deployment pipeline
├── .gitlab-ci-setup.yml        ← Setup pipeline
├── setup-gitlab-ci.sh          ← Local setup script
├── CUSTOMER-README.md          ← Start here
├── SETUP-PIPELINE-GUIDE.md     ← Pipeline setup guide
├── QUICK-REFERENCE.md          ← This file
├── Dockerfile                  ← Container definition
├── deployment/                 ← CloudFormation, Terraform, K8s
├── scripts/                    ← Orchestration scripts
├── docs/                       ← Documentation
└── examples/                   ← Sample configurations
```

## Cost Estimate

**Monthly costs (us-east-1):**
- ECS Fargate: ~$30-50
- ECR Storage: ~$1-5
- S3 Storage: ~$1-10
- CloudWatch Logs: ~$1-5
- **Total: ~$35-70/month**

## Support Resources

- **Setup Issues:** `SETUP-PIPELINE-GUIDE.md`
- **Deployment Issues:** `docs/deployment-guide.md`
- **Troubleshooting:** `docs/troubleshooting.md`
- **GitLab CI/CD:** `GITLAB-DEPLOYMENT.md`
- **ECS Quick Start:** `QUICKSTART-ECS.md`

## Quick Links

- [GitLab CI/CD Docs](https://docs.gitlab.com/ee/ci/)
- [AWS ECS Docs](https://docs.aws.amazon.com/ecs/)
- [CloudFormation Docs](https://docs.aws.amazon.com/cloudformation/)
- [AWS CLI Reference](https://docs.aws.amazon.com/cli/)

## Security Checklist

- [ ] AWS credentials marked as Protected and Masked
- [ ] Using dedicated CI/CD IAM user (not personal credentials)
- [ ] S3 buckets have encryption enabled
- [ ] ECR image scanning enabled
- [ ] CloudWatch Logs configured
- [ ] IAM roles follow least privilege principle
- [ ] Access keys rotated regularly

## Next Steps After Setup

1. ✅ Verify all GitLab variables set
2. ✅ Push code to trigger pipeline
3. ✅ Monitor deployment in GitLab
4. ✅ Check ECS cluster in AWS Console
5. ✅ Run test task
6. ✅ Review CloudWatch Logs
7. ✅ Test with sample CSV file

## Emergency Contacts

For production issues:
1. Check CloudWatch Logs first
2. Review GitLab pipeline logs
3. Check AWS CloudFormation events
4. Contact your AWS support team if needed
