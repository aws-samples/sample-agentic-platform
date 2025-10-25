#!/bin/bash

# Echo how the script was called
echo "Called: $0 $*"

# Check if service name and type are provided and validate arguments
if [ $# -lt 2 ]; then
    echo "Usage: $0 <service-name> <type> [--build]"
    echo "  --build: Build and push container before deploying"
    exit 1
elif [ $# -eq 2 ]; then
    SERVICE_NAME=$1
    TYPE=$2
    BUILD_CONTAINER=false
elif [ $# -eq 3 ]; then
    if [ "$3" != "--build" ]; then
        echo "Error: Invalid third argument. Only '--build' is allowed."
        echo "Usage: $0 <service-name> <type> [--build]"
        echo "  --build: Build and push container before deploying"
        exit 1
    fi
    SERVICE_NAME=$1
    TYPE=$2
    BUILD_CONTAINER=true
else
    echo "Error: Too many arguments provided."
    echo "Usage: $0 <service-name> <type> [--build]"
    echo "  --build: Build and push container before deploying"
    exit 1
fi

# Build and push the container if requested
if [ "$BUILD_CONTAINER" = true ]; then
    echo "Building and pushing container..."
    ./deploy/build-container.sh $SERVICE_NAME $TYPE
    if [ $? -ne 0 ]; then
        echo "Error: Container build failed"
        exit 1
    fi
fi

# Deploy with Helm using values files
echo "Deploying $SERVICE_NAME to Kubernetes with Helm..."
helm upgrade --install $SERVICE_NAME ./k8s/helm/charts/agentic-service \
  -f k8s/helm/values/applications/${SERVICE_NAME}-values.yaml

echo "Deployment complete!"
