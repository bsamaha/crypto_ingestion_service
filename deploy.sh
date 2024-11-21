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

check_first_time_deployment() {
    # Check if namespace exists
    if ! kubectl get namespace $NAMESPACE >/dev/null 2>&1; then
        echo -e "${YELLOW}First time deployment detected - creating namespace${NC}"
        kubectl create namespace $NAMESPACE
        return 0
    fi
    
    # Check if secrets exist
    if ! kubectl get secret coinbase-secrets -n $NAMESPACE >/dev/null 2>&1; then
        echo -e "${YELLOW}Secrets not found - setting up environment${NC}"
        return 0
    fi
    
    # Check if regcred exists
    if ! kubectl get secret regcred -n $NAMESPACE >/dev/null 2>&1; then
        echo -e "${YELLOW}Docker credentials not found - setting up environment${NC}"
        return 0
    fi
    
    return 1
}

setup_docker_credentials() {
    if [ -z "$DOCKER_USERNAME" ] || [ -z "$DOCKER_PASSWORD" ]; then
        echo -e "${YELLOW}Please enter Docker Hub credentials:${NC}"
        read -p "Username: " DOCKER_USERNAME
        read -s -p "Password: " DOCKER_PASSWORD
        echo
    fi
    
    echo "Logging into Docker Hub..."
    echo "$DOCKER_PASSWORD" | docker login -u "$DOCKER_USERNAME" --password-stdin
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
    
    # Check if secrets exist
    if kubectl get secret coinbase-secrets -n $NAMESPACE >/dev/null 2>&1; then
        echo -e "${GREEN}Secrets already exist${NC}"
        
        # Prompt to update
        read -p "Do you want to update the secrets? (y/n) " UPDATE_SECRETS
        if [[ $UPDATE_SECRETS != "y" ]]; then
            return
        fi
    fi
    
    echo -e "${YELLOW}Setting up Coinbase API credentials${NC}"
    
    # Prompt for required values with validation
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

    # Export variables for envsubst
    export COINBASE_API_KEY
    export COINBASE_API_SECRET
    
    # Create secrets from template
    echo "Creating Kubernetes secrets..."
    envsubst '${COINBASE_API_KEY} ${COINBASE_API_SECRET}' < k8s/overlays/dev/secrets.template.yaml | kubectl apply -n $NAMESPACE -f -
    
    # Cleanup exported variables
    unset COINBASE_API_KEY
    unset COINBASE_API_SECRET
    
    if [ $? -eq 0 ]; then
        echo -e "${GREEN}Successfully created/updated secrets${NC}"
    else
        echo -e "${RED}Failed to create/update secrets${NC}"
        exit 1
    fi
}

verify_kafka() {
    echo "Verifying Kafka connectivity..."
    if ! kubectl get namespace kafka >/dev/null 2>&1; then
        echo -e "${RED}Error: Kafka namespace not found${NC}"
        exit 1
    fi
    
    if ! kubectl wait --for=condition=ready pod -l app.kubernetes.io/name=kafka -n kafka --timeout=30s; then
        echo -e "${RED}Error: Kafka pods not ready${NC}"
        exit 1
    fi
}

deploy_app() {
    echo "Deploying application..."
    # Replace image in deployment
    kubectl set image deployment/coinbase-ws \
        coinbase-ws=${IMAGE_NAME}:${IMAGE_TAG} \
        -n ${NAMESPACE} || true
    
    kubectl apply -f k8s/base/network-policy.yaml -n $NAMESPACE
    kustomize build k8s/base | kubectl apply -n $NAMESPACE -f -
}

verify_deployment() {
    echo "Verifying deployment..."
    
    if ! kubectl wait --for=condition=available deployment/coinbase-ws -n $NAMESPACE --timeout=60s; then
        echo -e "${RED}Error: Deployment not ready${NC}"
        exit 1
    fi
    
    # Check pod health
    POD_NAME=$(kubectl get pods -n $NAMESPACE -l app=coinbase-ws -o jsonpath="{.items[0].metadata.name}")
    if ! kubectl exec $POD_NAME -n $NAMESPACE -- curl -s http://localhost:8000/health; then
        echo -e "${RED}Error: Health check failed${NC}"
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

# Main execution
echo "Namespace: $NAMESPACE"
echo "Image tag: $IMAGE_TAG"

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