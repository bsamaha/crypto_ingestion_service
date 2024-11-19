#!/bin/bash
set -e

# Configuration
NAMESPACE="coinbase-dev"
IMAGE_NAME="coinbase-websocket"
IMAGE_TAG="dev"

echo "🔧 Setting up development environment..."

# Create namespace if it doesn't exist
kubectl create namespace $NAMESPACE --dry-run=client -o yaml | kubectl apply -f -

# Build and load the image into k3s
echo "🏗️ Building development image..."
docker build -t $IMAGE_NAME:$IMAGE_TAG .

# Import image into k3s (if using k3d)
echo "📥 Importing image into k3s..."
k3d image import $IMAGE_NAME:$IMAGE_TAG -c mycluster

# Apply secrets
echo "🔐 Applying secrets..."
kubectl apply -f k8s/overlays/dev/secrets.yaml -n $NAMESPACE

# Apply Kubernetes manifests using kustomize
echo "📦 Deploying to development environment..."
kubectl apply -k k8s/overlays/dev -n $NAMESPACE

# Wait for deployment
echo "⏳ Waiting for deployment to be ready..."
kubectl rollout status deployment/dev-coinbase-ws -n $NAMESPACE

# Port forward for local access
echo "🔄 Setting up port forward..."
kubectl port-forward svc/dev-coinbase-ws 8000:8000 -n $NAMESPACE &
PORT_FORWARD_PID=$!

# Function to clean up
cleanup() {
    echo "🧹 Cleaning up..."
    kill $PORT_FORWARD_PID
    echo "✨ Development environment shutdown complete"
}
trap cleanup EXIT

# Show logs
echo "📜 Streaming logs..."
kubectl logs -f -l app=coinbase-ws -n $NAMESPACE 