#!/bin/bash
set -e  # Exit on any error

# Container configuration
CONTAINER_NAME="coinbase-ws"
IMAGE_NAME="coinbase-websocket"
PORT=8000

echo "🔍 Checking for existing container..."
if [ "$(docker ps -aq -f name=$CONTAINER_NAME)" ]; then
    echo "🛑 Stopping existing container..."
    docker stop $CONTAINER_NAME || true
    echo "🗑️ Removing existing container..."
    docker rm $CONTAINER_NAME || true
fi

echo "🧹 Cleaning up any dangling images..."
docker image prune -f

echo "🏗️ Building new image..."
docker build -t $IMAGE_NAME .

echo "🚀 Starting container..."
docker run -d \
    --name $CONTAINER_NAME \
    -p $PORT:$PORT \
    --env-file .env \
    --restart unless-stopped \
    $IMAGE_NAME

echo "⏳ Waiting for container to start..."
sleep 5

echo "✅ Verifying container is running..."
if [ "$(docker ps -q -f name=$CONTAINER_NAME)" ]; then
    echo "✨ Container is running successfully!"
    echo "📊 Health check endpoint: http://localhost:$PORT/health"
    echo "📈 Metrics endpoint: http://localhost:$PORT/metrics"
    echo ""
    echo "Useful commands:"
    echo "  - View logs: docker logs -f $CONTAINER_NAME"
    echo "  - Stop container: docker stop $CONTAINER_NAME"
    echo "  - Remove container: docker rm $CONTAINER_NAME"
    echo "  - Container shell: docker exec -it $CONTAINER_NAME /bin/bash"
    
    # Verify environment variables
    echo ""
    echo "🔍 Verifying environment variables..."
    docker exec $CONTAINER_NAME env | grep -E "COINBASE_API_|LOG_LEVEL|METRICS_PORT" || {
        echo "❌ Environment variables not set properly!"
        exit 1
    }
else
    echo "❌ Container failed to start!"
    echo "Checking container logs:"
    docker logs $CONTAINER_NAME
    exit 1
fi

# Optional: Show initial logs
echo ""
echo "📜 Initial container logs:"
docker logs $CONTAINER_NAME