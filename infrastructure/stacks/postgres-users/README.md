# PostgreSQL Users Setup Stack

This stack handles PostgreSQL user and database creation that must run after the platform-eks stack is deployed. It creates database users, databases, and configures basic database access permissions.

**Note**: This stack only handles infrastructure-level database setup (users, databases, permissions). Application-level schema migrations are handled separately through Alembic.

## Prerequisites

1. **Platform-EKS stack deployed** - This stack must be deployed first
2. **AWS CLI configured** with appropriate permissions
3. **Network connectivity** to PostgreSQL Aurora cluster (either direct VPC access or proxy)

## Configuration

### Variables

- `platform_config_parameter_name`: SSM parameter name containing platform configuration (default: `/agentic-platform/config/dev`)
- `use_local_proxy`: Whether to use localhost proxy instead of direct connection (default: `false`)

### Connection Methods

**Direct Connection** (`use_local_proxy = false`):
- Requires running from within the VPC or with VPC connectivity
- Uses the actual PostgreSQL Aurora endpoint
- Requires SSL connection

**Proxy Connection** (`use_local_proxy = true`):
- Uses localhost:5432 connection
- Requires port forward on 5432 through the bastion host.
- Disables SSL for local connection

## Deployment

```bash
cd infrastructure/stacks/postgres-users/
terraform init
terraform plan
terraform apply
```

## What This Stack Creates

- **Database users** for applications (LiteLLM, etc.)
- **Application databases** (separate databases for different services)
- **User permissions** and access controls
- **Secrets in AWS Secrets Manager** for application database credentials

## What This Stack Does NOT Handle

- **Application schema migrations** - These are handled by Alembic
- **Table creation** - Managed by application code
- **Data seeding** - Handled by application initialization
- **Schema versioning** - Managed through Alembic migrations

## Troubleshooting

### Connection Issues
- Verify platform-eks stack is deployed and PostgreSQL is accessible
- Check network connectivity to Aurora cluster
- Ensure AWS credentials have access to Secrets Manager and SSM Parameter Store

### Proxy Setup
If using `use_local_proxy = true`, set up port forwarding:
```bash
# Example: Port forward through bastion host
ssh -L 5432:postgres-endpoint:5432 bastion-host
```
