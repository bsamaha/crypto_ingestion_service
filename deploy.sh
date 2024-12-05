#!/bin/bash

# Default values
NAMESPACE="trading"
IMAGE_TAG=${IMAGE_TAG:-"latest"}
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
    echo "  -v, --version        Image version/tag [default: latest]"
    echo "  -h, --help           Show this help message"
}

verify_prerequisites() {
    echo -e "${YELLOW}Verifying prerequisites...${NC}"
    
    # Check if namespace exists
    if ! kubectl get namespace $NAMESPACE >/dev/null 2>&1; then
        echo -e "${RED}Error: Namespace '$NAMESPACE' does not exist${NC}"
        exit 1
    fi
    
    # Check if secret exists and has required fields
    if ! kubectl get secret coinbase-secrets -n $NAMESPACE >/dev/null 2>&1; then
        echo -e "${RED}Error: Secret 'coinbase-secrets' not found in namespace '$NAMESPACE'${NC}"
        echo "Please create the secret manually before deploying"
        exit 1
    fi
    
    # Verify secret has required fields
    local required_fields=("COINBASE_API_KEY" "COINBASE_API_SECRET")
    for field in "${required_fields[@]}"; do
        if ! kubectl get secret coinbase-secrets -n $NAMESPACE -o jsonpath="{.data.$field}" >/dev/null 2>&1; then
            echo -e "${RED}Error: Required field '$field' not found in secret 'coinbase-secrets'${NC}"
            exit 1
        fi
    done
    
    echo -e "${GREEN}Prerequisites verified successfully${NC}"
}

verify_registry_connection() {
    echo -e "${YELLOW}Verifying registry connection...${NC}"
    if ! curl -k -s "https://${REGISTRY_HOST}:${REGISTRY_PORT}/v2/_catalog" > /dev/null; then
        echo -e "${RED}Cannot access registry at ${REGISTRY_HOST}:${REGISTRY_PORT}${NC}"
        exit 1
    fi
    echo -e "${GREEN}Registry connection successful${NC}"
}

deploy_app() {
    echo "Deploying application..."
    
    # Update the image and tag in the kustomization file
    sed -i "s|newName: .*|newName: ${REGISTRY_HOST}:${REGISTRY_PORT}/${IMAGE_NAME}|" k8s/base/kustomization.yaml
    sed -i "s|newTag: .*|newTag: ${IMAGE_TAG}|" k8s/base/kustomization.yaml
    
    # Apply secrets first
    if [ -f k8s/base/secrets.yaml ]; then
        echo "Applying secrets..."
        kubectl apply -f k8s/base/secrets.yaml -n $NAMESPACE
    else
        echo -e "${RED}Error: secrets.yaml not found in k8s/base/${NC}"
        exit 1
    fi
    
    # Apply kustomization using kubectl
    if ! kubectl apply -k k8s/base -n $NAMESPACE; then
        echo -e "${RED}Failed to apply kustomization${NC}"
        exit 1
    fi
    
    # Apply network policy
    kubectl apply -f k8s/base/network-policy.yaml -n $NAMESPACE
}

verify_deployment() {
    echo "Verifying deployment..."
    
    if ! kubectl wait --for=condition=available deployment/coinbase-ws -n $NAMESPACE --timeout=60s; then
        echo -e "${RED}Error: Deployment not ready${NC}"
        kubectl get pods -n $NAMESPACE
        kubectl describe deployment coinbase-ws -n $NAMESPACE
        exit 1
    fi
    
    POD_NAME=$(kubectl get pods -n $NAMESPACE -l app=coinbase-ws -o jsonpath="{.items[0].metadata.name}")
    if [ -n "$POD_NAME" ]; then
        echo "Waiting for pod health check..."
        sleep 10
        if ! kubectl exec $POD_NAME -n $NAMESPACE -- curl -s http://localhost:8000/health; then
            echo -e "${RED}Error: Health check failed${NC}"
            kubectl logs $POD_NAME -n $NAMESPACE
            exit 1
        fi
    else
        echo -e "${RED}Error: No pods found${NC}"
        exit 1
    fi
    
    echo -e "${GREEN}Deployment verified successfully${NC}"
}

main() {
    # Parse command line arguments
    while [[ $# -gt 0 ]]; do
        case $1 in
            -n|--namespace)
                NAMESPACE="$2"
                shift 2
                ;;
            -v|--version)
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
    
    echo "Namespace: $NAMESPACE"
    echo "Image tag: $IMAGE_TAG"
    
    # Verify prerequisites
    verify_prerequisites
    
    # Verify registry connection
    verify_registry_connection
    
    # Deploy application
    deploy_app
    
    # Verify deployment
    verify_deployment
    
    echo -e "${GREEN}Deployment completed successfully${NC}"
}

# Run main function
main "$@"