# CodeBuild Manual Destroy Configuration

This document provides the CodeBuild configuration changes needed to manually destroy the Terraform infrastructure.

## Overview

The bootstrap CodeBuild project can be configured to either deploy or destroy infrastructure by modifying the build commands. This is useful for testing, cleanup, or emergency teardown scenarios.

## Configuration Options

### Standard Deployment Configuration

Use this configuration for normal infrastructure deployment:

```yaml
  build:
    commands:
      - echo "Creating Terraform plan..."
      - terraform plan -out=tfplan -input=false
      
      - echo "Applying Terraform plan..."
      - terraform apply -auto-approve tfplan
      
      - echo "Deployment completed. Outputs:"
      - terraform output -json | jq

```

### Destroy Configuration

⚠️ **WARNING**: This configuration will destroy all infrastructure managed by Terraform.

Use this configuration to tear down the infrastructure:

```yaml
  build:
    commands:
      - echo "🚨 DESTROYING Terraform infrastructure..."
      - echo "This will remove all resources managed by Terraform"
    
      - echo "Creating destroy plan..."
      - terraform plan -destroy -out=destroy-plan -input=false
    
      - echo "Applying destroy plan..."
      - terraform apply -auto-approve destroy-plan
    
      - echo "✅ Terraform destroy completed successfully!"
      - echo "All infrastructure resources have been removed."
```

## How to Use

1. **Navigate to AWS CodeBuild Console**
   - Go to the AWS CodeBuild service in your AWS console
   - Find your `agentptfm-bootstrap` project

2. **Edit Build Specification**
   - Click on your CodeBuild project
   - Go to "Edit" → "Buildspec"
   - Replace the `build` section with either configuration above

3. **Start Build**
   - Click "Start build" to execute the configuration
   - Monitor the build logs carefully

## Safety Considerations

### Before Destroying Infrastructure

- ✅ **Backup Data**: Ensure all important data is backed up
- ✅ **Verify Environment**: Confirm you're targeting the correct environment
- ✅ **Team Notification**: Notify team members before destroying shared resources
- ✅ **Dependencies**: Check for any dependent services or applications

### During Destruction

- 👀 **Monitor Logs**: Watch the build logs for any errors
- ⏱️ **Allow Time**: Destruction can take 15-30 minutes
- 🚫 **Don't Interrupt**: Let the process complete fully

### After Destruction

- ✅ **Verify Cleanup**: Check AWS console to ensure resources are removed
- 📝 **Document**: Record the destruction for audit purposes
- 🔄 **State Cleanup**: Consider cleaning up Terraform state if needed

## Troubleshooting

### Common Issues

**Build Fails During Destroy:**
- Check for resources with dependencies that prevent deletion
- Some resources may need manual cleanup (e.g., non-empty S3 buckets)

**Partial Destruction:**
- Re-run the destroy configuration
- Manually clean up remaining resources if necessary

**State Lock Issues:**
- Check DynamoDB for stuck locks
- May need to manually release locks in extreme cases

## Recovery

To redeploy after destruction:
1. Switch back to the standard deployment configuration
2. Run the CodeBuild project again
3. Infrastructure will be recreated from scratch

---

**Note**: This is a powerful operation that cannot be easily undone. Use with caution and ensure you have proper backups and authorization before proceeding.
