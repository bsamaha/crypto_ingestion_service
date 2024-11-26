#!/bin/bash

# Default values
NAMESPACE="trading"
IMAGE_TAG="1.0.0"
REGISTRY_HOST=${REGISTRY_HOST:-"192.168.1.221"}
REGISTRY_PORT=${REGISTRY_PORT:-"5001"}
IMAGE_NAME="coinbase-data-ingestion-service"
FULL_IMAGE_NAME="${REGISTRY_HOST}:${REGISTRY_PORT}/${IMAGE_NAME}"

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Help function
show_help() {
    echo "Usage: ./deploy.sh [options]"
    echo
    echo "Options:"
    echo "  -n, --namespace       Kubernetes namespace [default: trading]"
    echo "  -t, --tag            Docker image tag [default: 1.0.0]"
    echo "  -h, --help           Show this help message"
}

# Add this function after the show_help() function
select_image_version() {
    local default_tag="latest"
    
    # Get available tags from registry
    echo -e "${YELLOW}Fetching available tags from registry...${NC}"
    local tags_json=$(curl -sk "https://${REGISTRY_HOST}:${REGISTRY_PORT}/v2/${IMAGE_NAME}/tags/list")
    
    if [ $? -ne 0 ]; then
        echo -e "${RED}Failed to fetch tags from registry${NC}"
        echo -e "${YELLOW}Defaulting to 'latest' tag${NC}"
        echo "$default_tag"
        return
    fi
    
    echo "Available tags:"
    echo "$tags_json" | jq -r '.tags[]' | nl
    
    echo -e "\nSelect tag (press Enter for 'latest'):"
    read -r tag_choice
    
    if [ -z "$tag_choice" ]; then
        echo "$default_tag"
    else
        # Get the selected tag from the list
        selected_tag=$(echo "$tags_json" | jq -r ".tags[$((tag_choice-1))]" 2>/dev/null)
        if [ -n "$selected_tag" ] && [ "$selected_tag" != "null" ]; then
            echo "$selected_tag"
        else
            echo -e "${RED}Invalid selection. Using 'latest'${NC}"
            echo "$default_tag"
        fi
    fi
}

setup_namespaces() {
    echo -e "${YELLOW}Setting up required namespaces...${NC}"
    
    # Array of required namespaces and their labels
    declare -A namespaces=(
        ["trading"]="trading"
        ["kafka"]="kafka"
        ["monitoring"]="monitoring"
    )
    
    for ns in "${!namespaces[@]}"; do
        if ! kubectl get namespace $ns >/dev/null 2>&1; then
            echo "Creating namespace: $ns"
            kubectl create namespace $ns
        fi
        
        echo "Labeling namespace: $ns"
        kubectl label namespace $ns name=${namespaces[$ns]} --overwrite
    done
}

check_dependencies() {
    echo -e "${YELLOW}Checking dependencies...${NC}"

    # Check for jq
    if ! command -v jq &> /dev/null; then
        echo -e "${YELLOW}Installing jq...${NC}"
        sudo apt-get update && sudo apt-get install -y jq
        if ! command -v jq &> /dev/null; then
            echo -e "${RED}Failed to install jq. Please install manually.${NC}"
            exit 1
        fi
    fi

    # Check Docker permissions
    if ! groups | grep -q docker; then
        echo -e "${YELLOW}Adding user to docker group...${NC}"
        sudo usermod -aG docker $USER
        echo -e "${YELLOW}Please log out and back in for changes to take effect${NC}"
        echo -e "${YELLOW}For now, running with sudo...${NC}"
        export DOCKER_SUDO="sudo"
    else
        export DOCKER_SUDO=""
    fi
    
    # Check for kubectl kustomize first
    if ! kubectl kustomize --help >/dev/null 2>&1; then
        echo -e "${YELLOW}Installing kustomize via kubectl...${NC}"
        # Download the latest release
        curl -s "https://raw.githubusercontent.com/kubernetes-sigs/kustomize/master/hack/install_kustomize.sh" | bash
        chmod +x kustomize
        sudo mv kustomize /usr/local/bin/
        
        # Verify installation
        if ! command -v kustomize &> /dev/null; then
            echo -e "${RED}Failed to install kustomize. Please install manually.${NC}"
            exit 1
        fi
    fi
}


check_first_time_deployment() {
    if ! kubectl get namespace $NAMESPACE >/dev/null 2>&1; then
        echo -e "${YELLOW}First time deployment detected - creating namespace${NC}"
        kubectl create namespace $NAMESPACE
        return 0
    fi
    
    if ! kubectl get secret dev-coinbase-secrets -n $NAMESPACE >/dev/null 2>&1; then
        echo -e "${YELLOW}Secrets not found - setting up environment${NC}"
        return 0
    fi
    
    if ! kubectl get secret regcred -n $NAMESPACE >/dev/null 2>&1; then
        echo -e "${YELLOW}Docker credentials not found - setting up environment${NC}"
        return 0
    fi
    
    return 1
}

setup_docker_credentials() {
    # Check for existing Docker config
    if [ -f ~/.docker/config.json ]; then
        # Extract credentials from docker config
        DOCKER_USERNAME=$(jq -r '.auths["https://index.docker.io/v1/"].auth' ~/.docker/config.json | base64 -d | cut -d: -f1)
        DOCKER_PASSWORD=$(jq -r '.auths["https://index.docker.io/v1/"].auth' ~/.docker/config.json | base64 -d | cut -d: -f2)
        
        if [ -n "$DOCKER_USERNAME" ] && [ -n "$DOCKER_PASSWORD" ]; then
            echo "Using existing Docker credentials for user: $DOCKER_USERNAME"
            export DOCKER_USERNAME
            export DOCKER_PASSWORD
            return 0
        fi
    fi
    
    # Fall back to manual entry if credentials not found or invalid
    echo -e "${YELLOW}Please enter Docker Hub credentials:${NC}"
    read -p "Username: " DOCKER_USERNAME
    read -s -p "Password: " DOCKER_PASSWORD
    echo
    
    echo "Logging into Docker Hub..."
    echo "$DOCKER_PASSWORD" | $DOCKER_SUDO docker login -u "$DOCKER_USERNAME" --password-stdin
    
    export DOCKER_USERNAME
    export DOCKER_PASSWORD
}

setup_docker_secret() {
    kubectl create secret docker-registry regcred \
        --docker-server=https://index.docker.io/v1/ \
        --docker-username=$DOCKER_USERNAME \
        --docker-password=$DOCKER_PASSWORD \
        --namespace=$NAMESPACE \
        --dry-run=client -o yaml | kubectl apply -f -
}

build_env_file() {
    echo -e "${YELLOW}Checking for existing secrets...${NC}"
    
    if kubectl get secret dev-coinbase-secrets -n $NAMESPACE >/dev/null 2>&1; then
        echo -e "${GREEN}Secrets already exist${NC}"
        read -p "Do you want to update the secrets? (y/n) " UPDATE_SECRETS
        if [[ $UPDATE_SECRETS != "y" ]]; then
            return
        fi
    fi
    
    echo -e "${YELLOW}Setting up Coinbase API credentials${NC}"
    
    while true; do
        read -p "Coinbase API Key: " COINBASE_API_KEY
        if [[ -n "$COINBASE_API_KEY" ]]; then
            break
        fi
        echo -e "${RED}API Key cannot be empty${NC}"
    done
    
    while true; do
        read -s -p "Coinbase API Secret: " COINBASE_API_SECRET
        echo
        if [[ -n "$COINBASE_API_SECRET" ]]; then
            break
        fi
        echo -e "${RED}API Secret cannot be empty${NC}"
    done

    export COINBASE_API_KEY
    export COINBASE_API_SECRET
    
    echo "Creating Kubernetes secrets..."
    cp k8s/overlays/dev/secrets.template.yaml k8s/overlays/dev/secrets.yaml
    envsubst '${COINBASE_API_KEY} ${COINBASE_API_SECRET}' < k8s/overlays/dev/secrets.template.yaml > k8s/overlays/dev/secrets.yaml
    
    unset COINBASE_API_KEY
    unset COINBASE_API_SECRET
}

verify_kafka() {
    echo "Verifying Kafka connectivity..."
    if ! kubectl get namespace kafka >/dev/null 2>&1; then
        echo -e "${YELLOW}Warning: Kafka namespace not found${NC}"
        read -p "Continue without Kafka? (y/n) " CONTINUE
        if [[ $CONTINUE != "y" ]]; then
            exit 1
        fi
    else
        # Check for Strimzi Kafka cluster pods
        if ! kubectl wait --for=condition=ready pod -l strimzi.io/cluster=trading-cluster -n kafka --timeout=30s 2>/dev/null; then
            echo -e "${YELLOW}Warning: Kafka pods not ready${NC}"
            read -p "Continue without Kafka? (y/n) " CONTINUE
            if [[ $CONTINUE != "y" ]]; then
                exit 1
            fi
        fi
    fi
}

configure_registry_access() {
    echo "Configuring registry access..."
    
    # Create registry secret for pulling images from local registry
    kubectl create secret docker-registry local-registry-cred \
        --docker-server="https://${REGISTRY_HOST}:${REGISTRY_PORT}" \
        --docker-username="" \
        --docker-password="" \
        --docker-email="noreply@local.registry" \
        --namespace=$NAMESPACE \
        --dry-run=client -o yaml | kubectl apply -f -
        
    # Add the certificate to the secret using k3s certificate path
    local cert_data=$(cat /etc/rancher/k3s/certs/registry.crt | base64 -w 0)
    kubectl create secret generic registry-cert \
        --from-literal=ca.crt="$cert_data" \
        --namespace=$NAMESPACE \
        --dry-run=client -o yaml | kubectl apply -f -
        
    # Update the default service account to use local-registry-cred
    kubectl patch serviceaccount default \
        -p "{\"imagePullSecrets\": [{\"name\": \"local-registry-cred\"}]}" \
        -n $NAMESPACE
}

verify_registry_connection() {
    echo -e "${YELLOW}Verifying registry connection...${NC}"
    if ! curl --cacert /etc/rancher/k3s/certs/registry.crt -s "https://${REGISTRY_HOST}:${REGISTRY_PORT}/v2/_catalog" > /dev/null; then
        echo -e "${RED}Cannot access registry at ${REGISTRY_HOST}:${REGISTRY_PORT}${NC}"
        echo "Please ensure:"
        echo "1. Registry container is running"
        echo "2. Registry is accessible at ${REGISTRY_HOST}:${REGISTRY_PORT}"
        echo "3. Certificates are properly configured"
        exit 1
    fi
    echo -e "${GREEN}Registry connection successful${NC}"
}

deploy_app() {
    echo "Deploying application..."
    
    # Update the image and tag in the kustomization file
    sed -i "s|newName: .*|newName: ${REGISTRY_HOST}:${REGISTRY_PORT}/${IMAGE_NAME}|" k8s/overlays/dev/kustomization.yaml
    sed -i "s|newTag: .*|newTag: ${IMAGE_TAG}|" k8s/overlays/dev/kustomization.yaml
    
    # Apply kustomization using kubectl
    kubectl apply -k k8s/overlays/dev -n $NAMESPACE
    
    if [ $? -ne 0 ]; then
        echo -e "${RED}Failed to apply kustomization${NC}"
        exit 1
    fi
    
    # Apply network policy
    kubectl apply -f k8s/base/network-policy.yaml -n $NAMESPACE
}

verify_deployment() {
    echo "Verifying deployment..."
    
    if ! kubectl wait --for=condition=available deployment/dev-coinbase-ws -n $NAMESPACE --timeout=60s; then
        echo -e "${RED}Error: Deployment not ready${NC}"
        kubectl get pods -n $NAMESPACE
        kubectl describe deployment dev-coinbase-ws -n $NAMESPACE
        exit 1
    fi
    
    POD_NAME=$(kubectl get pods -n $NAMESPACE -l app=coinbase-ws -o jsonpath="{.items[0].metadata.name}")
    if [ -n "$POD_NAME" ]; then
        echo "Waiting for pod health check..."
        sleep 10  # Give the health endpoint time to start
        if ! kubectl exec $POD_NAME -n $NAMESPACE -- curl -s http://localhost:8000/health; then
            echo -e "${RED}Error: Health check failed${NC}"
            kubectl logs $POD_NAME -n $NAMESPACE
            exit 1
        fi
    else
        echo -e "${RED}Error: No pods found${NC}"
        exit 1
    fi
}

verify_certificate_access() {
    echo -e "${YELLOW}Verifying registry certificate access...${NC}"
    if [ ! -f "/etc/rancher/k3s/certs/registry.crt" ]; then
        echo -e "${RED}Cannot access registry certificate at /etc/rancher/k3s/certs/registry.crt${NC}"
        echo "Please ensure:"
        echo "1. Certificate exists at the correct path"
        echo "2. You have sufficient permissions to read the certificate"
        exit 1
    fi
    echo -e "${GREEN}Registry certificate accessible${NC}"
}

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        -n|--namespace)
            NAMESPACE="$2"
            shift 2
            ;;
        -t|--tag)
            IMAGE_TAG="$2"
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

# Main execution
echo "Namespace: $NAMESPACE"
echo "Image tag: $IMAGE_TAG"

# Check dependencies
check_dependencies

# Setup required namespaces
setup_namespaces

# Check if this is a first time deployment
if check_first_time_deployment; then
    setup_docker_credentials
    setup_docker_secret
    build_env_file
fi

# Verify Kafka is available
verify_kafka

# Verify certificate access
verify_certificate_access

# Configure registry access
configure_registry_access

# Verify registry connection
verify_registry_connection

# Before deploy_app, add:
IMAGE_TAG=$(select_image_version)
FULL_IMAGE_NAME="${REGISTRY_HOST}:${REGISTRY_PORT}/${IMAGE_NAME}:${IMAGE_TAG}"
echo -e "${GREEN}Using image: ${FULL_IMAGE_NAME}${NC}"

# Deploy application
deploy_app

# Verify deployment
verify_deployment

echo -e "${GREEN}Deployment process completed${NC}"