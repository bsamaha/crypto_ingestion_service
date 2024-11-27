#!/bin/bash

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

# Default values
REGISTRY="192.168.1.221:5001"
IMAGE_NAME="coinbase-data-ingestion-service"
VERSION_FILE=".version"

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
    echo "  -n, --name       Image name [default: coinbase-data-ingestion-service]"
    echo "  -h, --help       Show this help message"
    echo
    echo "Current version: $CURRENT_VERSION"
    echo "Registry: $REGISTRY"
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

# Prompt for version update
prompt_version_update

# Move these lines AFTER prompt_version_update since CURRENT_VERSION might change
FULL_IMAGE_NAME="${REGISTRY}/${IMAGE_NAME}"
VERSION_TAG="${FULL_IMAGE_NAME}:${CURRENT_VERSION}"
LATEST_TAG="${FULL_IMAGE_NAME}:latest"

# Build the image
echo -e "${YELLOW}Building image ${VERSION_TAG}${NC}"
if ! docker build --no-cache -t "${VERSION_TAG}" -t "${LATEST_TAG}" .; then
    echo -e "${RED}Build failed${NC}"
    exit 1
fi

# Verify local images
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

# Verify local images
verify_docker_image "${VERSION_TAG}"
verify_docker_image "${LATEST_TAG}"

# Test registry connectivity
echo -e "${YELLOW}Testing registry connectivity...${NC}"
if ! curl -k -f "https://${REGISTRY}/v2/_catalog" >/dev/null 2>&1; then
    echo -e "${RED}Cannot connect to registry at ${REGISTRY}${NC}"
    exit 1
fi

# Push images with retry logic
if ! push_with_retry "${VERSION_TAG}"; then
    echo -e "${RED}Failed to push version tag${NC}"
    exit 1
fi

if ! push_with_retry "${LATEST_TAG}"; then
    echo -e "${RED}Failed to push latest tag${NC}"
    exit 1
fi

# Verify remote image
echo -e "${YELLOW}Verifying remote image...${NC}"
docker rmi "${VERSION_TAG}" "${LATEST_TAG}"
if ! docker pull "${VERSION_TAG}"; then
    echo -e "${RED}Failed to verify remote image${NC}"
    exit 1
fi

verify_docker_image "${VERSION_TAG}"

echo -e "${GREEN}Successfully built and pushed version ${CURRENT_VERSION}${NC}"