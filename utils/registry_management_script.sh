r16@Alienware-R16:~$ cat registry_management.sh
#!/bin/bash

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

# Registry configuration
REGISTRY_HOST="192.168.1.221"
REGISTRY_PORT="5001"

# Function to format JSON output
format_json() {
    if command -v jq &> /dev/null; then
        jq '.'
    else
        python3 -m json.tool 2>/dev/null || cat
    fi
}

# Function to check if registry is running
check_registry() {
    if ! docker ps | grep -q "registry"; then
        echo -e "${RED}Error: Registry container is not running${NC}"
        echo -e "${YELLOW}Please start the registry container first:${NC}"
        echo "docker start registry"
        exit 1
    fi
}

# Function to list repositories
list_repositories() {
    echo -e "${YELLOW}Listing all repositories:${NC}"
    curl -sk "https://${REGISTRY_HOST}:${REGISTRY_PORT}/v2/_catalog" | format_json
}

# Function to list tags
list_tags() {
    local repo=$1
    echo -e "${YELLOW}Listing tags for ${repo}:${NC}"
    curl -sk "https://${REGISTRY_HOST}:${REGISTRY_PORT}/v2/${repo}/tags/list" | format_json
}

# Function to run garbage collection
run_gc() {
    echo -e "${YELLOW}Running garbage collection...${NC}"

    check_registry

    echo -e "${YELLOW}Starting garbage collection...${NC}"
    docker exec registry registry garbage-collect /etc/docker/registry/config.yml

    if [ $? -eq 0 ]; then
        echo -e "${GREEN}Garbage collection completed successfully${NC}"
        echo -e "${YELLOW}Restarting registry container to fully clean up space...${NC}"
        docker restart registry
        echo -e "${GREEN}Registry restarted${NC}"
    else
        echo -e "${RED}Garbage collection failed${NC}"
        exit 1
    fi
}

# Function to delete an entire repository
delete_repository() {
    local repo=$1
    echo -e "${YELLOW}Deleting entire repository: ${repo}${NC}"

    # First try to get all tags
    local tags_response=$(curl -sk "https://${REGISTRY_HOST}:${REGISTRY_PORT}/v2/${repo}/tags/list")

    if [[ $tags_response == *"tags\":null"* ]] || [[ $tags_response == *"tags\":[]"* ]]; then
        echo -e "${YELLOW}Repository exists but has no valid tags. Attempting direct cleanup...${NC}"

        # Execute cleanup directly in the registry container
        docker exec registry sh -c "rm -rf /var/lib/registry/docker/registry/v2/repositories/${repo}"

        if [ $? -eq 0 ]; then
            echo -e "${GREEN}Successfully removed repository directory${NC}"
            echo -e "${YELLOW}Running garbage collection to clean up...${NC}"
            run_gc
        else
            echo -e "${RED}Failed to remove repository directory${NC}"
            exit 1
        fi
    else
        echo -e "${YELLOW}Repository has tags. Deleting them first...${NC}"
        local tags=$(echo $tags_response | python3 -c "import sys, json; print('\n'.join(json.load(sys.stdin).get('tags', [])))" 2>/dev/null)

        for tag in $tags; do
            delete_tag "$repo" "$tag"
        done
    fi
}

# Function to delete a specific tag
delete_tag() {
    local repo=$1
    local tag=$2

    echo -e "${YELLOW}Getting manifest for ${repo}:${tag}...${NC}"

    # Get the manifest and its digest
    local manifest_response=$(curl -isk "https://${REGISTRY_HOST}:${REGISTRY_PORT}/v2/${repo}/manifests/${tag}" \
        -H "Accept: application/vnd.docker.distribution.manifest.v2+json" \
        -H "Accept: application/vnd.docker.distribution.manifest.list.v2+json" \
        -H "Accept: application/vnd.oci.image.manifest.v1+json")

    # Extract Docker-Content-Digest from headers
    local digest=$(echo "$manifest_response" | grep -i 'Docker-Content-Digest: ' | cut -d' ' -f2 | tr -d '\r')

    if [ -n "$digest" ]; then
        echo -e "${GREEN}Found digest: ${digest}${NC}"
        echo -e "${YELLOW}Deleting ${repo}:${tag}...${NC}"

        local delete_response=$(curl -sk -X DELETE "https://${REGISTRY_HOST}:${REGISTRY_PORT}/v2/${repo}/manifests/${digest}")

        if [ -z "$delete_response" ]; then
            echo -e "${GREEN}Successfully deleted ${repo}:${tag}${NC}"
        else
            echo -e "${RED}Error deleting image: ${delete_response}${NC}"
        fi
    else
        echo -e "${RED}Could not find digest for ${repo}:${tag}${NC}"
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
            echo "Usage: $0 tags <repository>"
            exit 1
        fi
        list_tags "$2"
        ;;
    "delete")
        if [ -z "$2" ]; then
            echo -e "${RED}Error: Repository name required${NC}"
            echo "Usage: $0 delete <repository> [tag]"
            exit 1
        fi
        if [ -z "$3" ]; then
            delete_repository "$2"
        else
            delete_tag "$2" "$3"
        fi
        ;;
    "gc")
        run_gc
        ;;
    *)
        echo "Usage: $0 {list|tags <repo>|delete <repo> [tag]|gc}"
        exit 1
        ;;
esac