# OIDC Setup Guide for GitLab CI/CD

## What is OIDC?

OpenID Connect (OIDC) allows GitLab CI/CD to authenticate with AWS using temporary, short-lived tokens instead of long-lived access keys. This provides enhanced security and eliminates the need to manage static credentials.

## Benefits of OIDC vs Access Keys

| Feature | OIDC | Access Keys |
|---------|------|-------------|
| **Security** | ✅ Temporary tokens (1 hour) | ❌ Long-lived credentials |
| **Rotation** | ✅ Automatic | ❌ Manual rotation required |
| **Compromise Risk** | ✅ Low (tokens expire quickly) | ❌ High (permanent until rotated) |
| **Compliance** | ✅ Better audit trail | ❌ Static credentials |
| **Management** | ✅ No key management | ❌ Key storage and rotation |

## How It Works

1. **GitLab generates OIDC token** when pipeline runs
2. **AWS STS validates token** against configured trust policy
3. **AWS returns temporary credentials** (AccessKey, SecretKey, SessionToken)
4. **Pipeline uses temporary credentials** for AWS operations
5. **Credentials expire automatically** after 1 hour

## Setup Process

### Prerequisites

- AWS CLI installed and configured with admin permissions
- GitLab project with CI/CD enabled
- GitLab project ID (found in Project Settings → General)

### Step 1: Run Setup Script

```bash
chmod +x setup-gitlab-ci.sh
./setup-gitlab-ci.sh
```

The script will:
1. Create S3 buckets with encryption and versioning
2. Create OIDC Identity Provider for GitLab
3. Create IAM role with trust policy for your GitLab project
4. Attach necessary permissions to the role

### Step 2: Configure GitLab Variables

Add these variables to **Settings → CI/CD → Variables**:

| Variable | Value | Description |
|----------|-------|-------------|
| `AWS_REGION` | `us-east-1` | AWS region |
| `AWS_ACCOUNT_ID` | `123456789012` | Your AWS account ID |
| `AWS_ROLE_ARN` | `arn:aws:iam::123456789012:role/GitLabCIRole` | IAM role ARN |
| `SOURCE_BUCKET` | `atx-test-source-123456789012` | S3 source bucket |
| `RESULTS_BUCKET` | `atx-test-results-123456789012` | S3 results bucket |

**Note:** No `AWS_ACCESS_KEY_ID` or `AWS_SECRET_ACCESS_KEY` needed!

### Step 3: Test the Pipeline

Push code to trigger the pipeline:

```bash
git add .
git commit -m "Test OIDC authentication"
git push origin main
```

## Trust Policy Explained

The IAM role trust policy restricts access to:

- **Specific GitLab project** (your project ID)
- **Main branch only** (ref:main)
- **GitLab.com domain** (or your GitLab instance)

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "Federated": "arn:aws:iam::ACCOUNT:oidc-provider/gitlab.com"
      },
      "Action": "sts:AssumeRoleWithWebIdentity",
      "Condition": {
        "StringEquals": {
          "gitlab.com:aud": "https://gitlab.com",
          "gitlab.com:sub": "project_path:*:ref_type:branch:ref:main"
        },
        "StringLike": {
          "gitlab.com:project_id": "YOUR_PROJECT_ID"
        }
      }
    }
  ]
}
```

## Pipeline Configuration

The `.gitlab-ci.yml` uses OIDC authentication:

```yaml
.aws_oidc_auth: &aws_oidc_auth
  id_tokens:
    GITLAB_OIDC_TOKEN:
      aud: https://gitlab.com
  before_script:
    - # Install AWS CLI
    - # Assume role with OIDC token
    - # Export temporary credentials
```

## Troubleshooting

### Common Issues

#### 1. "AssumeRoleWithWebIdentity failed"

**Cause:** Trust policy mismatch or incorrect project ID

**Solution:**
- Verify GitLab project ID is correct
- Check trust policy conditions
- Ensure pipeline runs on main branch

#### 2. "Invalid identity token"

**Cause:** OIDC provider not configured correctly

**Solution:**
- Verify OIDC provider exists in AWS IAM
- Check thumbprint is correct
- Ensure GitLab URL matches

#### 3. "Access denied" during AWS operations

**Cause:** IAM role permissions insufficient

**Solution:**
- Check IAM role has necessary permissions
- Verify resource ARNs in policy
- Test with broader permissions first

### Debugging Steps

1. **Check OIDC token:**
   ```yaml
   script:
     - echo "Token audience: $(echo $GITLAB_OIDC_TOKEN | base64 -d | jq -r .aud)"
     - echo "Token subject: $(echo $GITLAB_OIDC_TOKEN | base64 -d | jq -r .sub)"
   ```

2. **Verify role assumption:**
   ```yaml
   script:
     - aws sts get-caller-identity
     - aws sts assume-role-with-web-identity --role-arn $AWS_ROLE_ARN --role-session-name test --web-identity-token $GITLAB_OIDC_TOKEN
   ```

3. **Test permissions:**
   ```yaml
   script:
     - aws s3 ls
     - aws ecr describe-repositories
   ```

## Security Best Practices

### 1. Least Privilege Permissions

Only grant permissions needed for the pipeline:

```json
{
  "Effect": "Allow",
  "Action": [
    "ecr:GetAuthorizationToken",
    "ecr:BatchCheckLayerAvailability",
    "s3:GetObject",
    "s3:PutObject"
  ],
  "Resource": "arn:aws:s3:::atx-test-*/*"
}
```

### 2. Restrict to Specific Branches

Limit OIDC access to main branch only:

```json
{
  "StringEquals": {
    "gitlab.com:sub": "project_path:*:ref_type:branch:ref:main"
  }
}
```

### 3. Monitor and Audit

- Enable CloudTrail for API calls
- Monitor AssumeRoleWithWebIdentity events
- Set up alerts for unusual activity

### 4. Regular Review

- Review IAM role permissions quarterly
- Update trust policy if project structure changes
- Monitor for unused permissions

## Migration from Access Keys

If migrating from access keys:

1. **Run new setup script** to create OIDC role
2. **Update GitLab variables** (remove access keys, add role ARN)
3. **Test pipeline** with OIDC
4. **Delete old IAM user** and access keys
5. **Update documentation** for team

## Advanced Configuration

### Multiple Branches

To allow multiple branches:

```json
{
  "StringLike": {
    "gitlab.com:sub": "project_path:*:ref_type:branch:ref:*"
  }
}
```

### Multiple Projects

To share role across projects:

```json
{
  "StringLike": {
    "gitlab.com:project_id": ["12345", "67890"]
  }
}
```

### Custom Session Duration

Extend session duration (max 12 hours):

```yaml
script:
  - aws sts assume-role-with-web-identity \
    --duration-seconds 43200 \
    --role-arn $AWS_ROLE_ARN \
    --web-identity-token $GITLAB_OIDC_TOKEN
```

## Resources

- [AWS IAM OIDC Documentation](https://docs.aws.amazon.com/IAM/latest/UserGuide/id_roles_providers_create_oidc.html)
- [GitLab OIDC Documentation](https://docs.gitlab.com/ee/ci/cloud_services/aws/)
- [AWS STS AssumeRoleWithWebIdentity](https://docs.aws.amazon.com/STS/latest/APIReference/API_AssumeRoleWithWebIdentity.html)

## Support

For issues with OIDC setup:

1. Check pipeline logs for specific error messages
2. Verify trust policy conditions match your setup
3. Test role assumption manually with AWS CLI
4. Review CloudTrail logs for authentication attempts

The OIDC approach provides significantly better security than access keys while simplifying credential management!