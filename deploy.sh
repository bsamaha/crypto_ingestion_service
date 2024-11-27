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

    # Check for yq
    if ! command -v yq &> /dev/null; then
        echo -e "${YELLOW}Installing yq...${NC}"
        sudo wget https://github.com/mikefarah/yq/releases/latest/download/yq_linux_amd64 -O /usr/bin/yq
        sudo chmod +x /usr/bin/yq
        if ! command -v yq &> /dev/null; then
            echo -e "${RED}Failed to install yq. Please install manually.${NC}"
            exit 1
        fi
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
    
    if ! kubectl get secret coinbase-secrets -n $NAMESPACE >/dev/null 2>&1; then
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
    echo -e "${YELLOW}Setting up application secrets...${NC}"
    
    # Create a temporary file for secrets
    TEMP_SECRETS=$(mktemp)
    
    # Prompt for API credentials with clear instructions
    echo -e "${YELLOW}Please paste your Coinbase API credentials:${NC}"
    echo -e "${GREEN}Note: Paste the credentials exactly as provided by Coinbase, including newlines${NC}"
    echo -e "API Key (format: organizations/...): "
    read -r API_KEY
    
    echo -e "\nAPI Secret (format: -----BEGIN EC PRIVATE KEY-----...): "
    echo -e "${YELLOW}Press Ctrl+D (or Ctrl+Z on Windows) after pasting the private key${NC}"
    API_SECRET=$(cat)
    
    # Validate API credentials format
    if [[ ! "$API_KEY" =~ ^organizations/.*$ ]]; then
        echo -e "${RED}Error: Invalid API key format. Should start with 'organizations/'${NC}"
        rm "$TEMP_SECRETS"
        exit 1
    fi
    
    if [[ ! "$API_SECRET" =~ "BEGIN EC PRIVATE KEY" ]]; then
        echo -e "${RED}Error: Invalid API secret format. Should be an EC private key${NC}"
        rm "$TEMP_SECRETS"
        exit 1
    fi
    
    # Create the secrets yaml with proper handling of newlines
    cat > "$TEMP_SECRETS" <<EOF
apiVersion: v1
kind: Secret
metadata:
  name: coinbase-secrets
type: Opaque
stringData:
  COINBASE_API_KEY: "${API_KEY}"
  COINBASE_API_SECRET: |
$(echo "$API_SECRET" | sed 's/^/    /')
EOF

    # Apply the secrets
    if ! kubectl apply -f "$TEMP_SECRETS" -n "$NAMESPACE"; then
        echo -e "${RED}Failed to apply secrets${NC}"
        rm "$TEMP_SECRETS"
        exit 1
    fi
    
    # Clean up
    rm "$TEMP_SECRETS"
    
    echo -e "${GREEN}Secrets configured successfully${NC}"
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
        --docker-server="${REGISTRY_HOST}:${REGISTRY_PORT}" \
        --docker-username="_" \
        --docker-password="_" \
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
    if ! curl -k -s "https://${REGISTRY_HOST}:${REGISTRY_PORT}/v2/_catalog" > /dev/null; then
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
    sed -i "s|newName: .*|newName: ${REGISTRY_HOST}:${REGISTRY_PORT}/${IMAGE_NAME}|" k8s/base/kustomization.yaml
    sed -i "s|newTag: .*|newTag: ${IMAGE_TAG}|" k8s/base/kustomization.yaml
    
    # Apply kustomization using kubectl
    kubectl apply -k k8s/base -n $NAMESPACE
    
    if [ $? -ne 0 ]; then
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
    
    echo "Verifying API credentials format..."
    CREDENTIALS_CHECK=$(kubectl exec $POD_NAME -n $NAMESPACE -- python3 -c "
from app.config import get_settings
from cryptography.hazmat.primitives.serialization import load_pem_private_key
try:
    settings = get_settings()
    # Try to load the private key to verify format
    key_bytes = settings.COINBASE_API_SECRET.encode()
    load_pem_private_key(key_bytes, password=None)
    print('API credentials format verified')
except Exception as e:
    print(f'Error: {str(e)}')
    exit(1)
")
    if [[ $? -ne 0 ]]; then
        echo -e "${RED}Error: API credentials validation failed${NC}"
        echo "$CREDENTIALS_CHECK"
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

setup_complete_deployment() {
    echo -e "${YELLOW}Starting complete deployment setup...${NC}"
    
    # 1. Create and label namespaces
    setup_namespaces
    
    # 2. Set up Docker credentials
    setup_docker_credentials
    setup_docker_secret
    
    # 3. Configure registry access
    configure_registry_access
    verify_registry_connection
    
    # 4. Set up secrets and config
    if check_first_time_deployment; then
        build_env_file
    fi
    
    # 5. Verify Kafka (if needed)
    verify_kafka
    
    # 6. Apply ConfigMap
    echo "Applying ConfigMap..."
    kubectl apply -f k8s/base/configmap.yaml -n "$NAMESPACE"
    
    # 7. Deploy the application
    deploy_app
    
    # 8. Verify deployment
    verify_deployment
    
    echo -e "${GREEN}Complete deployment setup finished successfully${NC}"
}

# Main script execution
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
    
    # Check dependencies
    check_dependencies
    
    # Run complete deployment
    setup_complete_deployment
}

# Run main function
main "$@"