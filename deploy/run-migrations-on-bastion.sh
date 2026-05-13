#!/bin/bash

echo "========================================="
echo "Running Database Migrations on Bastion Host"
echo "========================================="

# Check if alembic is available
if ! command -v alembic &> /dev/null; then
    echo "❌ Error: alembic not found. Please install it first:"
    echo "   pip install alembic"
    exit 1
fi

# Check if jq is available
if ! command -v jq &> /dev/null; then
    echo "❌ Error: jq not found. Please install it first:"
    echo "   sudo yum install jq -y"
    exit 1
fi

# Get the configuration from SSM Parameter Store
echo "🔍 Retrieving configuration from Parameter Store..."
CONFIG_JSON=$(aws ssm get-parameter \
    --name "/agentic-platform/config/agentcore-dev" \
    --with-decryption \
    --query 'Parameter.Value' \
    --output text)

if [ -z "$CONFIG_JSON" ]; then
    echo "❌ Error: Could not retrieve configuration from Parameter Store"
    exit 1
fi

# Parse the JSON configuration
PG_CONNECTION_URL=$(echo "$CONFIG_JSON" | jq -r '.PG_WRITER_ENDPOINT')
PG_PASSWORD_SECRET_ARN=$(echo "$CONFIG_JSON" | jq -r '.PG_PASSWORD_SECRET_ARN')

# Get the actual master username and password from Secrets Manager
echo "🔍 Retrieving database credentials from Secrets Manager..."
DB_CREDENTIALS=$(aws secretsmanager get-secret-value \
    --secret-id "$PG_PASSWORD_SECRET_ARN" \
    --query 'SecretString' \
    --output text)

DB_USERNAME=$(echo "$DB_CREDENTIALS" | jq -r '.username')
PG_PASSWORD=$(echo "$DB_CREDENTIALS" | jq -r '.password')

echo "   Username: $DB_USERNAME"

if [ -z "$PG_PASSWORD" ]; then
    echo "❌ Error: Could not retrieve database password"
    exit 1
fi

echo "✅ Configuration retrieved successfully"

# Create .env file with database configuration
echo "📝 Creating environment configuration..."
cat > .env << EOF
export PG_CONNECTION_URL=$PG_CONNECTION_URL
export PG_USER=postgres
export PG_READ_ONLY_USER=postgres
export PG_PASSWORD=$PG_PASSWORD
export PG_READ_ONLY_PASSWORD=$PG_PASSWORD
export PG_DATABASE=postgres
export ENVIRONMENT=local
EOF

# # Source the environment file
source .env

# # Run migrations
# echo "🚀 Running Alembic migrations..."
alembic upgrade head