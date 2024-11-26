#!/bin/bash

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

# Get script directory and project root
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
ENV_FILE="${PROJECT_ROOT}/.env"

# Load only registry-related environment variables
load_registry_env() {
    if [ ! -f "$ENV_FILE" ]; then
        echo -e "${RED}Error: .env file not found at ${ENV_FILE}${NC}"
        exit 1
    fi

    # Use grep to only get registry-related variables and properly handle them
    while IFS= read -r line; do
        # Skip comments and empty lines
        [[ $line =~ ^#.*$ ]] && continue
        [[ -z $line ]] && continue
        
        # Extract key and value using parameter expansion
        key=${line%%=*}
        value=${line#*=}
        
        # Only process registry and image related variables
        if [[ $key == "REGISTRY_HOST" ]] || [[ $key == "REGISTRY_PORT" ]] || [[ $key == "IMAGE_NAME" ]]; then
            # Remove any surrounding quotes and spaces
            value=$(echo "$value" | sed -e 's/^[[:space:]]*"//' -e 's/"[[:space:]]*$//' -e "s/^[[:space:]]*'//" -e "s/'[[:space:]]*$//")
            # Export the variable safely
            export "${key}=${value}"
        fi
    done < "$ENV_FILE"
}

# Load environment variables
load_registry_env

# Set defaults if not found in env file
REGISTRY_HOST=${REGISTRY_HOST:-"192.168.1.221"}
REGISTRY_PORT=${REGISTRY_PORT:-"5001"}

# Function to format JSON output without jq
format_json() {
    python -m json.tool 2>/dev/null || cat
}

delete_image() {
    local image_name=$1
    local tag=$2
    
    echo -e "${YELLOW}Getting digest for ${image_name}:${tag}...${NC}"
    
    # Get the digest for the image
    local digest=$(curl -sk "https://${REGISTRY_HOST}:${REGISTRY_PORT}/v2/${image_name}/manifests/${tag}" \
        -H "Accept: application/vnd.docker.distribution.manifest.v2+json" \
        | python -c "import sys, json; print(json.load(sys.stdin).get('config', {}).get('digest', ''))")
    
    if [ -n "$digest" ]; then
        echo -e "${GREEN}Deleting ${image_name}:${tag} (digest: ${digest})${NC}"
        curl -sk -X DELETE "https://${REGISTRY_HOST}:${REGISTRY_PORT}/v2/${image_name}/manifests/${digest}"
        echo -e "${GREEN}Delete request sent${NC}"
    else
        echo -e "${RED}Could not find digest for ${image_name}:${tag}${NC}"
    fi
}

list_repositories() {
    echo -e "${YELLOW}Listing all repositories:${NC}"
    curl -sk "https://${REGISTRY_HOST}:${REGISTRY_PORT}/v2/_catalog" | format_json
}

list_tags() {
    local repo=$1
    echo -e "${YELLOW}Listing tags for ${repo}:${NC}"
    curl -sk "https://${REGISTRY_HOST}:${REGISTRY_PORT}/v2/${repo}/tags/list" | format_json
}

run_gc() {
    echo -e "${YELLOW}Running garbage collection...${NC}"
    
    # For WSL2, we need to execute the command in WSL
    if [[ "$(uname -s)" == *"MINGW"* ]]; then
        echo -e "${YELLOW}Detected Git Bash, executing garbage collection through WSL...${NC}"
        wsl -e docker exec registry registry garbage-collect /etc/docker/registry/config.yml
    else
        # Direct execution for WSL or Linux
        docker exec registry registry garbage-collect /etc/docker/registry/config.yml
    fi
}

# Command processing
case "$1" in
    "list")
        list_repositories
        ;;
    "tags")
        if [ -z "$2" ]; then
            echo -e "${RED}Error: Repository name required${NC}"
            exit 1
        fi
        list_tags "$2"
        ;;
    "delete")
        if [ -z "$2" ] || [ -z "$3" ]; then
            echo -e "${RED}Error: Repository and tag required${NC}"
            exit 1
        fi
        delete_image "$2" "$3"
        ;;
    "gc")
        run_gc
        ;;
    *)
        echo "Usage: $0 {list|tags <repo>|delete <repo> <tag>|gc}"
        exit 1
        ;;
esac