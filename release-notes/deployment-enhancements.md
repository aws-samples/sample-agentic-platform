# Release Notes Deployment Enhancements

**Release Date**: October 2025  
**Type**: Enhancements

## Summary

This release improves the sample agentic platform's deployment process, documentation, and gateway configurations. The changes focus on making the platform more production-ready with better security practices, clearer deployment instructions, and improved service connectivity.

## Key Changes

### Documentation Enhancements
- **Bootstrap README**: Expanded from basic setup to comprehensive 10-section deployment guide
- **DEPLOYMENT.md**: Added Helm as required dependency for Kubernetes package management
- Added detailed sections for EKS access configuration, PostgreSQL setup, and testing procedures
- Included security warnings and best practices for IAM role configuration

### Infrastructure Improvements
- **EKS Configuration**: Added support for additional admin role ARNs for better access control
- **Bootstrap Template**: Enhanced with EKS public access configuration and admin role management
- **Access Control**: Implemented proper dependency ordering for EKS access entries

### Gateway and Service Enhancements
- **Service Endpoints**: Updated all gateway endpoints to include proper API paths (`/api/gateway-name`)
- **Secret Management**: 
  - Fixed LiteLLM key generation from placeholder to proper `sk-` prefixed keys
  - Updated secret references to use app-specific naming (`{app-name}-agent-secret`)
  - Enhanced IAM policies for gateway access to secrets
- **Memory Gateway**: Added LiteLLM secret access permissions
- **Retrieval Gateway**: Added comprehensive secrets policy for LiteLLM and agent secrets

### Kubernetes Configuration Updates
- **Helm Charts**: Updated deployment and external secrets templates for proper secret naming
- **Application Values**: Standardized gateway endpoint configurations across all applications:
  - agentic-chat, evaluator-optimizer, langgraph-chat, orchestrator, parallelization
  - Updated memory-gateway and retrieval-gateway configurations
  - Fixed prompt-chaining secret configuration key


### Local Docker Build and deploy scripts with --build flag
- **Enhanced parameter validation**: Deploy scripts now require both `<service-name>` and `<type>` parameters with optional `[--build]` flag
- **Multi-platform Docker support**: 
  - Added Docker buildx configuration for linux/amd64 and linux/arm64 architectures
  - Updated build-container.sh to use `--push` flag for direct ECR deployment
  - Improved build process with proper multi-platform builder setup
- **Script improvements**:
  - Fixed parameter ordering in deploy-gateways.sh to match new validation requirements
  - Enhanced error messages and usage instructions across all deployment scripts


## Issues Resolved
- #11 - Fixed manual deployment process issues
- #9 - Corrected deployment instruction ordering
- #6 - Clarified EKS console role creation during initial deployment

## Technical Details

- Gateway endpoint URLs now include API path prefixes (`/api/gateway-name`)
- Secret naming convention changed to app-specific format
- LiteLLM keys now use proper `sk-` prefix instead of placeholder values
