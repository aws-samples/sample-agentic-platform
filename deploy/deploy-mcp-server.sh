#!/bin/bash

# Simple deployment script for MCP servers
# Usage: ./deploy/deploy-mcp-server.sh <service-name> [--build]

echo "Called: $0 $*"

# Check arguments
if [ $# -lt 1 ]; then
    echo "Usage: $0 <service-name> [--build]"
    echo "  --build: Build and push container before deploying"
    exit 1
fi

SERVICE_NAME=$1
BUILD_CONTAINER=false

if [ $# -eq 2 ]; then
    if [ "$2" != "--build" ]; then
        echo "Error: Invalid argument. Only '--build' is allowed."
        echo "Usage: $0 <service-name> [--build]"
        exit 1
    fi
    BUILD_CONTAINER=true
fi

# Build and push the container if requested
if [ "$BUILD_CONTAINER" = true ]; then
    echo "Building and pushing container..."
    ./deploy/build-container.sh $SERVICE_NAME mcp_server
    if [ $? -ne 0 ]; then
        echo "Error: Container build failed"
        exit 1
    fi
fi

# Deploy with Helm using mcp-server chart
echo "Deploying $SERVICE_NAME MCP server to Kubernetes..."
helm upgrade --install $SERVICE_NAME ./k8s/helm/charts/mcp-server \
  -f k8s/helm/values/applications/${SERVICE_NAME}-values.yaml

if [ $? -eq 0 ]; then
    echo "✓ Deployment complete!"
    echo ""
    echo "Verify deployment:"
    echo "  kubectl get deployment $SERVICE_NAME"
    echo "  kubectl get pods -l app=$SERVICE_NAME"
    echo "  kubectl logs -l app=$SERVICE_NAME --tail=50"
else
    echo "✗ Deployment failed"
    exit 1
fi
