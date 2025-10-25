#!/bin/bash

# Echo how the script was called
echo "Called: $0 $*"

# Array of gateway services
GATEWAYS=(
    "memory-gateway"
    "retrieval-gateway"
)
TYPE="service" #hardcoded as gateways are "service"
BUILD_FLAG=""

# Check for build flag
if [ $# -eq 1 ] && [ "$1" = "--build" ]; then
    BUILD_FLAG="--build"
    echo "🔨 Build flag detected - will build containers before deploying"
fi

echo "========================================="
echo "Deploying All Gateways"
echo "========================================="

# Deploy each gateway
for gateway in "${GATEWAYS[@]}"; do
    echo ""
    echo "🚀 Deploying $gateway..."
    echo "----------------------------------------"
    
    ./deploy/deploy-application.sh "$gateway" $TYPE $BUILD_FLAG
    
    if [ $? -eq 0 ]; then
        echo "✅ $gateway deployed successfully"
    else
        echo "❌ Failed to deploy $gateway"
        exit 1
    fi
done

echo ""
echo "========================================="
echo "✅ All gateways deployed successfully!"
echo "=========================================" 