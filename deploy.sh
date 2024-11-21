#!/bin/bash

# Default values
NAMESPACE="trading"
IMAGE_TAG="1.0.0"
IMAGE_NAME="bsamaha/coinbase-data-ingestion-service"

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
        if ! kubectl wait --for=condition=ready pod -l app=kafka -n kafka --timeout=30s 2>/dev/null; then
            echo -e "${YELLOW}Warning: Kafka pods not ready${NC}"
            read -p "Continue without Kafka? (y/n) " CONTINUE
            if [[ $CONTINUE != "y" ]]; then
                exit 1
            fi
        fi
    fi
}

deploy_app() {
    echo "Deploying application..."
    
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

# Deploy application
deploy_app

# Verify deployment
verify_deployment

echo -e "${GREEN}Deployment process completed${NC}"