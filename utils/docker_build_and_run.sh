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
    set -a
    source "$ENV_FILE"
    set +a
else
    echo -e "${RED}No .env file found at ${ENV_FILE}${NC}"
    exit 1
fi

# Default values with ENV override
IMAGE_NAME=${IMAGE_NAME:-"coinbase-data-ingestion-service"}
VERSION_FILE="${PROJECT_ROOT}/.version"
REGISTRY_HOST=${REGISTRY_HOST:-"192.168.1.221"}
REGISTRY_PORT=${REGISTRY_PORT:-"5001"}
FULL_IMAGE_NAME="${REGISTRY_HOST}:${REGISTRY_PORT}/${IMAGE_NAME}"


# Create version file if it doesn't exist
if [ ! -f "$VERSION_FILE" ]; then
    echo "1.0.0" > "$VERSION_FILE"
fi

CURRENT_VERSION=$(cat "$VERSION_FILE")

# Help function
show_help() {
    echo "Usage: ./docker_build_and_push.sh [options]"
    echo
    echo "Options:"
    echo "  -n, --name       Image name [default: ${IMAGE_NAME}]"
    echo "  -r, --registry   Registry host [default: ${REGISTRY_HOST}]"
    echo "  -p, --port       Registry port [default: ${REGISTRY_PORT}]"
    echo "  -h, --help       Show this help message"
    echo
    echo "Current version: $CURRENT_VERSION"
}

increment_version() {
    local version=$1
    local major minor patch
    
    IFS='.' read -r major minor patch <<< "$version"
    
    case $2 in
        major)
            echo "$((major + 1)).0.0"
            ;;
        minor)
            echo "${major}.$((minor + 1)).0"
            ;;
        patch)
            echo "${major}.${minor}.$((patch + 1))"
            ;;
    esac
}

prompt_version_update() {
    echo -e "${YELLOW}Current version: $CURRENT_VERSION${NC}"
    echo "Do you want to increment the version? (y/n)"
    read -r response
    
    if [[ "$response" =~ ^[Yy]$ ]]; then
        echo "Select version increment type:"
        echo "1) Major (x.0.0)"
        echo "2) Minor (0.x.0)"
        echo "3) Patch (0.0.x)"
        read -r choice
        
        case $choice in
            1) NEW_VERSION=$(increment_version "$CURRENT_VERSION" "major");;
            2) NEW_VERSION=$(increment_version "$CURRENT_VERSION" "minor");;
            3) NEW_VERSION=$(increment_version "$CURRENT_VERSION" "patch");;
            *) echo -e "${RED}Invalid choice${NC}"; exit 1;;
        esac
        
        echo -e "${GREEN}New version will be: $NEW_VERSION${NC}"
        echo "Proceed? (y/n)"
        read -r confirm
        if [[ "$confirm" =~ ^[Yy]$ ]]; then
            echo "$NEW_VERSION" > "$VERSION_FILE"
            CURRENT_VERSION=$NEW_VERSION
        else
            echo "Keeping version $CURRENT_VERSION"
        fi
    fi
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

verify_docker_image() {
    local image_tag=$1
    echo -e "${YELLOW}Verifying image: ${image_tag}${NC}"
    
    # Check if image exists locally
    if ! docker image inspect "${image_tag}" >/dev/null 2>&1; then
        echo -e "${RED}Error: Image ${image_tag} not found locally${NC}"
        return 1
    fi
    
    # Check image size and display it
    local size=$(docker image inspect "${image_tag}" --format='{{.Size}}')
    local size_mb=$((size/1024/1024))
    echo -e "${GREEN}Local image size: ${size_mb}MB${NC}"
    
    if [ "$size" -eq 0 ]; then
        echo -e "${RED}Error: Image ${image_tag} has 0 byte size${NC}"
        return 1
    fi
    
    return 0
}

# Verify registry access
verify_registry() {
    echo -e "${YELLOW}Verifying registry access at ${REGISTRY_HOST}:${REGISTRY_PORT}${NC}"
    if ! curl -k -s "https://${REGISTRY_HOST}:${REGISTRY_PORT}/v2/_catalog" > /dev/null; then
        echo -e "${RED}Cannot access registry at ${REGISTRY_HOST}:${REGISTRY_PORT}${NC}"
        exit 1
    fi
}

push_with_retry() {
    local image_tag=$1
    local max_retries=3
    local retry_count=0
    
    while [ $retry_count -lt $max_retries ]; do
        echo -e "${YELLOW}Pushing ${image_tag} (Attempt $((retry_count + 1))/${max_retries})${NC}"
        
        if docker push "${image_tag}" 2>&1 | tee /tmp/push_output.log; then
            echo -e "${GREEN}Successfully pushed ${image_tag}${NC}"
            return 0
        fi
        
        echo -e "${RED}Push failed. Error output:${NC}"
        cat /tmp/push_output.log
        
        retry_count=$((retry_count + 1))
        if [ $retry_count -lt $max_retries ]; then
            echo "Waiting 10 seconds before retry..."
            sleep 10
        fi
    done
    
    echo -e "${RED}Failed to push after ${max_retries} attempts${NC}"
    return 1
}

# Verify registry access before proceeding
verify_registry

# Prompt for version update
prompt_version_update

# Build the image
echo -e "${YELLOW}Building image ${FULL_IMAGE_NAME}:${CURRENT_VERSION}${NC}"
if ! docker build --no-cache -t "${FULL_IMAGE_NAME}:${CURRENT_VERSION}" -t "${FULL_IMAGE_NAME}:latest" .; then
    echo -e "${RED}Build failed${NC}"
    exit 1
fi

# Verify local images
verify_docker_image "${FULL_IMAGE_NAME}:${CURRENT_VERSION}"
verify_docker_image "${FULL_IMAGE_NAME}:latest"

# Push images with retry logic
if ! push_with_retry "${FULL_IMAGE_NAME}:${CURRENT_VERSION}"; then
    echo -e "${RED}Failed to push version tag${NC}"
    exit 1
fi

if ! push_with_retry "${FULL_IMAGE_NAME}:latest"; then
    echo -e "${RED}Failed to push latest tag${NC}"
    exit 1
fi

# Verify remote image
echo -e "${YELLOW}Verifying remote image...${NC}"
docker rmi "${FULL_IMAGE_NAME}:${CURRENT_VERSION}" "${FULL_IMAGE_NAME}:latest"
if ! docker pull "${FULL_IMAGE_NAME}:${CURRENT_VERSION}"; then
    echo -e "${RED}Failed to verify remote image${NC}"
    exit 1
fi

# Show registry contents after push
echo -e "${YELLOW}Registry contents:${NC}"
curl -k "https://${REGISTRY_HOST}:${REGISTRY_PORT}/v2/_catalog"
echo -e "\n${YELLOW}Tags for ${IMAGE_NAME}:${NC}"
curl -k "https://${REGISTRY_HOST}:${REGISTRY_PORT}/v2/${IMAGE_NAME}/tags/list"

verify_docker_image "${FULL_IMAGE_NAME}:${CURRENT_VERSION}"

echo -e "${GREEN}Successfully built and pushed version ${CURRENT_VERSION}${NC}"