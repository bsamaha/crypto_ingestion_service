#!/bin/bash
# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

# Get the directory of the script and project root
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

# Load environment variables
ENV_FILE="${PROJECT_ROOT}/.env"
if [ -f "$ENV_FILE" ]; then
    echo -e "${GREEN}Loading configuration from ${ENV_FILE}${NC}"
    
    # Read variables carefully
    COINBASE_API_KEY=$(grep '^COINBASE_API_KEY=' "$ENV_FILE" | sed 's/^COINBASE_API_KEY=//')
    # Get the API secret as a single line
    COINBASE_API_SECRET=$(grep '^COINBASE_API_SECRET=' "$ENV_FILE" | sed 's/^COINBASE_API_SECRET=//')
    LOG_LEVEL=$(grep '^LOG_LEVEL=' "$ENV_FILE" | sed 's/^LOG_LEVEL=//' || echo "INFO")
    PRODUCT_IDS=$(grep '^PRODUCT_IDS=' "$ENV_FILE" | sed 's/^PRODUCT_IDS=//')
    CHANNELS=$(grep '^CHANNELS=' "$ENV_FILE" | sed 's/^CHANNELS=//')
    ENABLE_HEARTBEAT=$(grep '^ENABLE_HEARTBEAT=' "$ENV_FILE" | sed 's/^ENABLE_HEARTBEAT=//' | tr -d '[:space:]')
    ENABLE_DEBUG_METRICS=$(grep '^ENABLE_DEBUG_METRICS=' "$ENV_FILE" | sed 's/^ENABLE_DEBUG_METRICS=//' | tr -d '[:space:]')
    
    # Remove any trailing whitespace
    COINBASE_API_KEY=$(echo "$COINBASE_API_KEY" | tr -d '[:space:]')
    LOG_LEVEL=$(echo "$LOG_LEVEL" | tr -d '[:space:]')
else
    echo -e "${RED}No .env file found at ${ENV_FILE}${NC}"
    exit 1
fi

# Default values with ENV override
IMAGE_NAME=${IMAGE_NAME:-"coinbase-data-ingestion-service"}
REGISTRY_HOST=${REGISTRY_HOST:-"192.168.1.221"}
REGISTRY_PORT=${REGISTRY_PORT:-"5001"}
METRICS_PORT=${METRICS_PORT:-"8000"}
FULL_IMAGE_NAME="${REGISTRY_HOST}:${REGISTRY_PORT}/${IMAGE_NAME}"

# Help function
show_help() {
    echo "Usage: ./docker_run.sh [options]"
    echo
    echo "Options:"
    echo "  -n, --name       Image name [default: ${IMAGE_NAME}]"
    echo "  -r, --registry   Registry host [default: ${REGISTRY_HOST}]"
    echo "  -p, --port       Registry port [default: ${REGISTRY_PORT}]"
    echo "  -m, --metrics    Metrics port [default: ${METRICS_PORT}]"
    echo "  -h, --help       Show this help message"
}

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        -n|--name)
            IMAGE_NAME="$2"
            shift 2
            ;;
        -r|--registry)
            REGISTRY_HOST="$2"
            shift 2
            ;;
        -p|--port)
            REGISTRY_PORT="$2"
            shift 2
            ;;
        -m|--metrics)
            METRICS_PORT="$2"
            shift 2
            ;;
        -h|--help)
            show_help
            exit 0
            ;;
        *)
            echo -e "${RED}Unknown option: $1${NC}"
            show_help
            exit 1
            ;;
    esac
done

# Update FULL_IMAGE_NAME after parsing arguments
FULL_IMAGE_NAME="${REGISTRY_HOST}:${REGISTRY_PORT}/${IMAGE_NAME}"

# Verify required environment variables
if [ -z "$COINBASE_API_KEY" ] || [ -z "$COINBASE_API_SECRET" ]; then
    echo -e "${RED}Error: COINBASE_API_KEY and COINBASE_API_SECRET must be set in .env file${NC}"
    exit 1
fi

# Verify other important variables have defaults
: ${LOG_LEVEL:="INFO"}
: ${PRODUCT_IDS:='["BTC-USD","ETH-USD"]'}
: ${CHANNELS:='["candles","heartbeats"]'}
: ${ENABLE_HEARTBEAT:="true"}
: ${ENABLE_DEBUG_METRICS:="false"}
: ${METRICS_PORT:="8000"}

# Clean up any existing container with the same name
echo -e "${YELLOW}Cleaning up any existing container...${NC}"
docker rm -f "${IMAGE_NAME}" 2>/dev/null

echo -e "${YELLOW}Pulling latest image from registry...${NC}"
if ! docker pull "${FULL_IMAGE_NAME}:latest"; then
    echo -e "${RED}Failed to pull image${NC}"
    exit 1
fi

echo -e "${YELLOW}Starting container...${NC}"
docker run -d \
    --name "${IMAGE_NAME}" \
    -p "${METRICS_PORT}:8000" \
    -e COINBASE_API_KEY="$COINBASE_API_KEY" \
    -e COINBASE_API_SECRET="$COINBASE_API_SECRET" \
    -e KAFKA_ENABLED=false \
    -e LOG_LEVEL="$LOG_LEVEL" \
    -e METRICS_PORT=8000 \
    -e PRODUCT_IDS="$PRODUCT_IDS" \
    -e CHANNELS="$CHANNELS" \
    -e ENABLE_HEARTBEAT="$ENABLE_HEARTBEAT" \
    -e ENABLE_DEBUG_METRICS="$ENABLE_DEBUG_METRICS" \
    --restart unless-stopped \
    "${FULL_IMAGE_NAME}:latest"

if [ $? -eq 0 ]; then
    echo -e "${GREEN}Container started successfully${NC}"
    echo -e "${GREEN}Metrics available at http://localhost:${METRICS_PORT}/metrics${NC}"
    echo -e "${GREEN}Health check available at http://localhost:${METRICS_PORT}/health${NC}"
    
    # Show container logs
    echo -e "${YELLOW}Container logs:${NC}"
    docker logs -f "${IMAGE_NAME}"
else
    echo -e "${RED}Failed to start container${NC}"
    exit 1
fi 