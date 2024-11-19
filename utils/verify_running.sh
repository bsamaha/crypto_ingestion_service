#!/bin/bash

CONTAINER_NAME="coinbase-ws"
PORT=8000
TEMP_LOG=$(mktemp)
trap 'rm -f $TEMP_LOG' EXIT  # Clean up temp file on exit

# Check if container exists and is running
if [ ! "$(docker ps -q -f name=$CONTAINER_NAME)" ]; then
    echo "❌ Container is not running!"
    
    # Check if container exists but is stopped
    if [ "$(docker ps -aq -f status=exited -f name=$CONTAINER_NAME)" ]; then
        echo "Container exists but is stopped. Checking last logs:"
        docker logs --tail 50 $CONTAINER_NAME
    fi
    exit 1
fi

# Wait for services to be ready
echo "⏳ Waiting for services to be ready..."
sleep 5

# Check health endpoint
echo "🏥 Checking health endpoint..."
HEALTH_STATUS=$(curl -s -o /dev/null -w "%{http_code}" http://localhost:$PORT/health)
if [ "$HEALTH_STATUS" == "200" ]; then
    echo "✅ Health check passed"
else
    echo "❌ Health check failed with status: $HEALTH_STATUS"
    echo "Checking container logs:"
    docker logs $CONTAINER_NAME --tail 20
fi

# Check metrics endpoint
echo "📊 Checking metrics endpoint..."
METRICS_STATUS=$(curl -s -o /dev/null -w "%{http_code}" http://localhost:$PORT/metrics)
if [ "$METRICS_STATUS" == "200" ]; then
    echo "✅ Metrics endpoint accessible"
else
    echo "❌ Metrics endpoint failed with status: $METRICS_STATUS"
fi

# Check log file
echo "📝 Checking log file..."
if [ -f "coinbase_events.log" ]; then
    echo "✅ Log file exists"
    echo "Last 5 log entries:"
    tail -n 5 coinbase_events.log
else
    echo "❌ Log file not found"
fi

# Show container stats
echo ""
echo "📈 Container stats:"
docker stats $CONTAINER_NAME --no-stream --format "table {{.Container}}\t{{.CPUPerc}}\t{{.MemUsage}}\t{{.NetIO}}\t{{.BlockIO}}"