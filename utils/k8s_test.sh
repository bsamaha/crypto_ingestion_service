#!/bin/bash
set -e

NAMESPACE="coinbase-dev"

echo "🧪 Running Kubernetes integration tests..."

# Wait for service to be ready
echo "⏳ Waiting for service to be available..."
kubectl wait --for=condition=available deployment/dev-coinbase-ws -n $NAMESPACE --timeout=60s

# Test health endpoint
echo "🏥 Testing health endpoint..."
HEALTH_STATUS=$(curl -s -o /dev/null -w "%{http_code}" http://localhost:8000/health)
if [ "$HEALTH_STATUS" != "200" ]; then
    echo "❌ Health check failed with status: $HEALTH_STATUS"
    exit 1
fi

# Test metrics endpoint
echo "📊 Testing metrics endpoint..."
METRICS_STATUS=$(curl -s -o /dev/null -w "%{http_code}" http://localhost:8000/metrics)
if [ "$METRICS_STATUS" != "200" ]; then
    echo "❌ Metrics endpoint failed with status: $METRICS_STATUS"
    exit 1
fi

# Check logs for errors
echo "📝 Checking logs for errors..."
if kubectl logs -l app=coinbase-ws -n $NAMESPACE | grep -i error; then
    echo "⚠️ Found errors in logs"
    exit 1
fi

echo "✅ All tests passed!" 