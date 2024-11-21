#!/bin/bash

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

# Default values
IMAGE_NAME="bsamaha/coinbase-data-ingestion-service"
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
    echo "  -n, --name       Image name [default: bsamaha/coinbase-data-ingestion-service]"
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

# Build the image
echo -e "${YELLOW}Building image ${IMAGE_NAME}:${CURRENT_VERSION}${NC}"
docker build -t "${IMAGE_NAME}:${CURRENT_VERSION}" -t "${IMAGE_NAME}:latest" .

if [ $? -ne 0 ]; then
    echo -e "${RED}Build failed${NC}"
    exit 1
fi

# Push the image
echo -e "${YELLOW}Pushing image ${IMAGE_NAME}:${CURRENT_VERSION}${NC}"
docker push "${IMAGE_NAME}:${CURRENT_VERSION}"
docker push "${IMAGE_NAME}:latest"

if [ $? -eq 0 ]; then
    echo -e "${GREEN}Successfully built and pushed version ${CURRENT_VERSION}${NC}"
else
    echo -e "${RED}Failed to push image${NC}"
    exit 1
fi