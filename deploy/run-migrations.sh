#!/bin/bash

set -e  # Exit on any error

echo "========================================="
echo "Running Database Migrations"
echo "========================================="

# Check if alembic is available
if ! command -v alembic &> /dev/null; then
    echo "❌ Error: alembic not found. Please install it first:"
    echo "   pip install alembic"
    exit 1
fi

# Get bastion instance ID
echo "🔍 Finding bastion instance..."
INSTANCE_ID=$(aws ec2 describe-instances \
  --filters "Name=tag:Name,Values=*bastion-instance*" "Name=instance-state-name,Values=running" \
  --query "Reservations[].Instances[].InstanceId" \
  --output text)

if [ -z "$INSTANCE_ID" ]; then
    echo "❌ Error: Could not find running bastion instance"
    exit 1
fi

echo "✅ Found bastion instance: $INSTANCE_ID"

# Get database information from Parameter Store
echo "🔍 Getting database information from Parameter Store..."

# Determine environment (default to 'dev' if not set)
ENVIRONMENT=${ENVIRONMENT:-dev}
PARAMETER_PATH="/agentic-platform/config/${ENVIRONMENT}"

# Get all configuration from parameter store
CONFIG_JSON=$(aws ssm get-parameter --name "$PARAMETER_PATH" --query 'Parameter.Value' --output text)

if [ -z "$CONFIG_JSON" ]; then
    echo "❌ Error: Could not retrieve configuration from Parameter Store at path: $PARAMETER_PATH"
    exit 1
fi

# Extract database information from the JSON
WRITER_ENDPOINT=$(echo $CONFIG_JSON | jq -r '.PG_WRITER_ENDPOINT')
SECRET_ARN=$(echo $CONFIG_JSON | jq -r '.PG_PASSWORD_SECRET_ARN')
DB_USERNAME=$(echo $CONFIG_JSON | jq -r '.POSTGRES_MASTER_USERNAME')
CLUSTER_ID=$(echo $CONFIG_JSON | jq -r '.POSTGRES_CLUSTER_ID')
PG_DATABASE=$(echo $CONFIG_JSON | jq -r '.PG_DATABASE')

# Get the master password from Secrets Manager
echo "🔍 Retrieving database credentials from Secrets Manager..."
DB_CREDENTIALS=$(aws secretsmanager get-secret-value --secret-id $SECRET_ARN --query 'SecretString' --output text)
DB_PASSWORD=$(echo $DB_CREDENTIALS | jq -r '.password')

echo "✅ Database information retrieved from Parameter Store"
echo "   Cluster: $CLUSTER_ID"
echo "   Endpoint: $WRITER_ENDPOINT"
echo "   Username: $DB_USERNAME"
echo "   Database: $PG_DATABASE"

# Start port forwarding in background
echo "🚀 Starting port forwarding to database..."
aws ssm start-session \
  --target $INSTANCE_ID \
  --document-name AWS-StartPortForwardingSessionToRemoteHost \
  --parameters "portNumber=5432,localPortNumber=5432,host=$WRITER_ENDPOINT" &

PORT_FORWARD_PID=$!

# Function to cleanup on exit
cleanup() {
    echo ""
    echo "🧹 Cleaning up..."
    if [ ! -z "$PORT_FORWARD_PID" ]; then
        kill $PORT_FORWARD_PID 2>/dev/null || true
    fi
    # Clear sensitive environment variables
    unset PG_PASSWORD
    unset PG_READ_ONLY_PASSWORD
    echo "✅ Cleanup completed"
}

# Set trap to cleanup on script exit
trap cleanup EXIT

# Wait a moment for port forwarding to establish
echo "⏳ Waiting for port forwarding to establish..."
sleep 5

# Test database connection
echo "🔍 Testing database connection..."
if ! timeout 10 bash -c 'until nc -z localhost 5432; do sleep 1; done'; then
    echo "❌ Error: Could not establish connection to database"
    exit 1
fi

echo "✅ Database connection established"

# Set environment variables for alembic (no file creation)
export ENVIRONMENT=local
export PG_DATABASE=$PG_DATABASE
export PG_USER=$DB_USERNAME
export PG_READ_ONLY_USER=$DB_USERNAME
export PG_PASSWORD=$DB_PASSWORD
export PG_READ_ONLY_PASSWORD=$DB_PASSWORD
export PG_CONNECTION_URL=localhost

# Run migrations
echo "🚀 Running Alembic migrations..."
alembic upgrade head

echo ""
echo "========================================="
echo "✅ Database migrations completed!"
echo "========================================="
