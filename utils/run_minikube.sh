#!/bin/bash
set -e

# Add this function at the beginning of the script, after the configuration variables
check_pod_status() {
    local pod_name=$(kubectl get pods -n $NAMESPACE -l app=coinbase-ws -o jsonpath='{.items[0].metadata.name}')
    if [ -z "$pod_name" ]; then
        echo "❌ No pod found with label app=coinbase-ws"
        return 1
    fi

    echo "🔍 Checking pod $pod_name status..."
    
    # Get pod status
    local phase=$(kubectl get pod $pod_name -n $NAMESPACE -o jsonpath='{.status.phase}')
    local ready=$(kubectl get pod $pod_name -n $NAMESPACE -o jsonpath='{.status.containerStatuses[0].ready}')
    local restarts=$(kubectl get pod $pod_name -n $NAMESPACE -o jsonpath='{.status.containerStatuses[0].restartCount}')
    
    echo "Phase: $phase"
    echo "Ready: $ready"
    echo "Restarts: $restarts"
    
    # Get container status
    local state=$(kubectl get pod $pod_name -n $NAMESPACE -o jsonpath='{.status.containerStatuses[0].state}')
    if [[ $state == *"waiting"* ]]; then
        local reason=$(kubectl get pod $pod_name -n $NAMESPACE -o jsonpath='{.status.containerStatuses[0].state.waiting.reason}')
        local message=$(kubectl get pod $pod_name -n $NAMESPACE -o jsonpath='{.status.containerStatuses[0].state.waiting.message}')
        echo "Container waiting: $reason - $message"
    fi
}

# Configuration
NAMESPACE="coinbase-dev"
IMAGE_NAME="coinbase-websocket"
IMAGE_TAG="dev"
PORT=8000

# Start Minikube with Docker driver
echo "🔧 Starting Minikube..."
minikube start --driver=docker

# Create namespace if it doesn't exist
echo "🔧 Creating namespace..."
kubectl create namespace $NAMESPACE --dry-run=client -o yaml | kubectl apply -f -

# Build Docker image
echo "🏗️ Building development image..."
docker build -t $IMAGE_NAME:$IMAGE_TAG .

# Load image into Minikube
echo "📥 Importing image into Minikube..."
eval $(minikube docker-env)
docker build -t $IMAGE_NAME:$IMAGE_TAG .
eval $(minikube docker-env -u)

# Add this after the image build step and before applying secrets
echo "🔍 Checking for secrets file..."
SECRETS_PATH="k8s/overlays/dev/secrets.yaml"
if [ ! -f "$SECRETS_PATH" ]; then
    echo "⚠️ Secrets file not found, creating default secrets..."
    mkdir -p k8s/overlays/dev
    cat > "$SECRETS_PATH" << EOF
apiVersion: v1
kind: Secret
metadata:
  name: coinbase-secrets
type: Opaque
stringData:
  COINBASE_API_KEY: "default-api-key"
  COINBASE_API_SECRET: "default-api-secret"
  LOG_LEVEL: "INFO"
  METRICS_PORT: "8000"
EOF
    echo "✅ Created default secrets file at $SECRETS_PATH"
fi

# Continue with applying secrets
echo "🔐 Applying secrets..."
kubectl apply -f "$SECRETS_PATH" -n $NAMESPACE

# Apply Kubernetes manifests using kustomize
echo "📦 Deploying to development environment..."
kubectl apply -k k8s/overlays/dev -n $NAMESPACE


echo "⏳ Waiting for deployment to be ready..."
if ! kubectl rollout status deployment/dev-coinbase-ws -n $NAMESPACE --timeout=120s; then
    echo "❌ Deployment failed to roll out. Debugging information:"
    
    echo "📝 Pod status:"
    kubectl get pods -n $NAMESPACE -l app=coinbase-ws -o wide
    
    echo "📜 Pod logs:"
    kubectl logs -n $NAMESPACE -l app=coinbase-ws --tail=50
    
    echo "📊 Pod description:"
    kubectl describe pods -n $NAMESPACE -l app=coinbase-ws
    
    echo "🔍 Events:"
    kubectl get events -n $NAMESPACE --sort-by='.lastTimestamp'
    
    # Cleanup before exit
    cleanup
    exit 1
fi

# Port forward for local access
echo "🔄 Setting up port forward..."
kubectl port-forward svc/dev-coinbase-ws $PORT:$PORT -n $NAMESPACE &
PORT_FORWARD_PID=$!

# Function to clean up
cleanup() {
    echo "🧹 Cleaning up..."
    kill $PORT_FORWARD_PID 2>/dev/null || true
    kubectl delete namespace $NAMESPACE
    minikube stop
    echo "✨ Development environment shutdown complete"
}

# Only trap cleanup on script failure, not on success
trap 'cleanup' ERR

echo "✅ Setup complete! Your development environment is running."
echo "📊 Access the application at http://localhost:$PORT"
echo ""
echo "Useful commands:"
echo "  - View logs: kubectl logs -f -l app=coinbase-ws -n $NAMESPACE"
echo "  - Get pod status: kubectl get pods -n $NAMESPACE"
echo "  - Shell into pod: kubectl exec -it \$(kubectl get pods -n $NAMESPACE -l app=coinbase-ws -o jsonpath='{.items[0].metadata.name}') -n $NAMESPACE -- /bin/bash"
echo ""
echo "Press Ctrl+C to shutdown the development environment..."

# Wait indefinitely
wait $PORT_FORWARD_PID

# Show logs
echo "📜 Streaming logs..."
kubectl logs -f -l app=coinbase-ws -n $NAMESPACE &

# Run tests
echo "🧪 Running Kubernetes integration tests..."
kubectl wait --for=condition=available deployment/dev-coinbase-ws -n $NAMESPACE --timeout=60s

# Test health endpoint
HEALTH_STATUS=$(curl -s -o /dev/null -w "%{http_code}" http://localhost:$PORT/health)
if [ "$HEALTH_STATUS" != "200" ]; then
    echo "❌ Health check failed with status: $HEALTH_STATUS"
    exit 1
fi

# Test metrics endpoint
METRICS_STATUS=$(curl -s -o /dev/null -w "%{http_code}" http://localhost:$PORT/metrics)
if [ "$METRICS_STATUS" != "200" ]; then
    echo "❌ Metrics endpoint failed with status: $METRICS_STATUS"
    exit 1
fi

# Check logs for errors
if kubectl logs -l app=coinbase-ws -n $NAMESPACE | grep -i error; then
    echo "⚠️ Found errors in logs"
    exit 1
fi

echo "✅ All tests passed!"