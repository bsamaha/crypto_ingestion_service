#!/bin/bash

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

# Get script directory and load environment variables
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
ENV_FILE="${PROJECT_ROOT}/.env"

# Load environment variables safely
load_env() {
    if [ -f "$ENV_FILE" ]; then
        while IFS='=' read -r key value; do
            # Skip comments and empty lines
            [[ $key =~ ^#.*$ ]] && continue
            [[ -z $key ]] && continue
            
            # Remove any quotes from value
            value=$(echo "$value" | tr -d '"' | tr -d "'")
            
            # Export the variable
            export "$key=$value"
        done < "$ENV_FILE"
    else
        echo -e "${RED}No .env file found at ${ENV_FILE}${NC}"
        exit 1
    fi
}

load_env

# Set defaults if not in env
REGISTRY_HOST=${REGISTRY_HOST:-"192.168.1.221"}
REGISTRY_PORT=${REGISTRY_PORT:-"5001"}

# Function to pretty print JSON without jq
pretty_print_json() {
    python -m json.tool 2>/dev/null || echo
}

show_help() {
    echo -e "${GREEN}Registry Management Script${NC}"
    echo
    echo "Usage:"
    echo "  $0 [command]"
    echo
    echo "Commands:"
    echo "  list                 List all repositories"
    echo "  tags <repo>          List tags for a repository"
    echo "  delete <repo> <tag>  Delete a specific tag"
    echo "  gc                   Run garbage collection"
    echo "  info                 Show registry information"
}

delete_image() {
    local image_name=$1
    local tag=$2
    
    # Get the digest for the image
    local digest=$(curl -sk "https://${REGISTRY_HOST}:${REGISTRY_PORT}/v2/${image_name}/manifests/${tag}" \
        -H "Accept: application/vnd.docker.distribution.manifest.v2+json" \
        | python -c "import sys, json; print(json.load(sys.stdin).get('config', {}).get('digest', ''))")
    
    if [ -n "$digest" ]; then
        echo -e "${YELLOW}Deleting ${image_name}:${tag} (digest: ${digest})${NC}"
        curl -sk -X DELETE "https://${REGISTRY_HOST}:${REGISTRY_PORT}/v2/${image_name}/manifests/${digest}"
        echo -e "${GREEN}Delete request sent${NC}"
    else
        echo -e "${RED}Could not find digest for ${image_name}:${tag}${NC}"
    fi
}

case "$1" in
    "list")
        echo -e "${YELLOW}Listing all repositories:${NC}"
        curl -sk "https://${REGISTRY_HOST}:${REGISTRY_PORT}/v2/_catalog" | pretty_print_json
        ;;
    "tags")
        if [ -z "$2" ]; then
            echo -e "${RED}Error: Repository name required${NC}"
            exit 1
        fi
        echo -e "${YELLOW}Listing tags for $2:${NC}"
        curl -sk "https://${REGISTRY_HOST}:${REGISTRY_PORT}/v2/$2/tags/list" | pretty_print_json
        ;;
    "delete")
        if [ -z "$2" ] || [ -z "$3" ]; then
            echo -e "${RED}Error: Repository and tag required${NC}"
            exit 1
        fi
        delete_image "$2" "$3"
        ;;
    "gc")
        echo -e "${YELLOW}Running garbage collection...${NC}"
        docker exec -it registry registry garbage-collect /etc/docker/registry/config.yml
        ;;
    "info")
        echo -e "${GREEN}Registry Information${NC}"
        echo -e "Registry URL: https://${REGISTRY_HOST}:${REGISTRY_PORT}"
        echo -e "\n${YELLOW}Available repositories:${NC}"
        curl -sk "https://${REGISTRY_HOST}:${REGISTRY_PORT}/v2/_catalog" | pretty_print_json
        ;;
    *)
        show_help
        ;;
esac