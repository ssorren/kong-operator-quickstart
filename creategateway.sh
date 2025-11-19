#!/usr/bin/env bash

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Function to print colored output
print_step() {
    echo -e "${BLUE}==>${NC} ${GREEN}$1${NC}"
}

print_info() {
    echo -e "${YELLOW}$1${NC}"
}

print_error() {
    echo -e "${RED}ERROR: $1${NC}"
}

print_success() {
    echo -e "${GREEN}✓ $1${NC}"
}

# Function to prompt user to continue
prompt_continue() {
    echo ""
    read -p "Press Enter to continue or Ctrl+C to exit..."
    echo ""
}

# Function to check if command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Welcome message
clear
echo -e "${GREEN}================================${NC}"
echo -e "${GREEN}Kong Operator Quickstart Setup${NC}"
echo -e "${GREEN}================================${NC}"
echo ""

# Check prerequisites
print_step "Checking prerequisites..."
missing_deps=()
for cmd in kubectl helm envsubst jq curl; do
    if command_exists "$cmd"; then
        print_success "$cmd found"
    else
        print_error "$cmd not found"
        missing_deps+=("$cmd")
    fi
done

if [ ${#missing_deps[@]} -ne 0 ]; then
    print_error "Missing required dependencies: ${missing_deps[*]}"
    echo "Please install them before continuing."
    exit 1
fi

prompt_continue

# Step 2: Environment Variables
print_step "Step 2: Setting up Environment Variables"
echo ""

# Prompt for Control Plane Name
read -p "Enter CONTROL_PLANE_NAME [default: ko-quickstart]: " CONTROL_PLANE_NAME
CONTROL_PLANE_NAME=${CONTROL_PLANE_NAME:-ko-quickstart}
export CONTROL_PLANE_NAME

# Prompt for Kong Gateway Image
read -p "Enter KONG_GATEWAY_IMAGE [default: kong/kong-gateway:3.12]: " KONG_GATEWAY_IMAGE
KONG_GATEWAY_IMAGE=${KONG_GATEWAY_IMAGE:-kong/kong-gateway:3.12}
export KONG_GATEWAY_IMAGE

# Prompt for Konnect API Endpoint
read -p "Enter KONNECT_API_ENDPOINT [default: us.api.konghq.com]: " KONNECT_API_ENDPOINT
KONNECT_API_ENDPOINT=${KONNECT_API_ENDPOINT:-us.api.konghq.com}
export KONNECT_API_ENDPOINT

# Prompt for Load Balancer Ports
read -p "Enter LB_HTTP_PORT [default: 8080]: " LB_HTTP_PORT
LB_HTTP_PORT=${LB_HTTP_PORT:-8080}
export LB_HTTP_PORT

read -p "Enter LB_HTTPS_PORT [default: 8443]: " LB_HTTPS_PORT
LB_HTTPS_PORT=${LB_HTTPS_PORT:-8443}
export LB_HTTPS_PORT

# Prompt for Personal Access Token
echo ""
if [ -n "$PAT" ]; then
    print_info "Found existing PAT environment variable."
    read -p "Use existing PAT? [Y/n]: " USE_EXISTING_PAT
    USE_EXISTING_PAT=${USE_EXISTING_PAT:-Y}
    
    if [[ ! "$USE_EXISTING_PAT" =~ ^[Yy] ]]; then
        print_info "You can get your Personal Access Token from: https://cloud.konghq.com/global/account/tokens"
        read -sp "Enter your Konnect Personal Access Token (PAT): " PAT
        export PAT
        echo ""
    else
        print_success "Using existing PAT"
    fi
else
    print_info "You can get your Personal Access Token from: https://cloud.konghq.com/global/account/tokens"
    read -sp "Enter your Konnect Personal Access Token (PAT): " PAT
    export PAT
    echo ""
fi

if [ -z "$PAT" ]; then
    print_error "PAT is required!"
    exit 1
fi

echo ""
print_success "Environment variables configured:"
echo "  CONTROL_PLANE_NAME: $CONTROL_PLANE_NAME"
echo "  KONG_GATEWAY_IMAGE: $KONG_GATEWAY_IMAGE"
echo "  KONNECT_API_ENDPOINT: $KONNECT_API_ENDPOINT"
echo "  LB_HTTP_PORT: $LB_HTTP_PORT"
echo "  LB_HTTPS_PORT: $LB_HTTPS_PORT"
echo "  PAT: ****"

prompt_continue

# Step 3: Check Kong Operator
print_step "Step 3: Checking if kong-operator pod is running..."
echo ""
kubectl --namespace kong-system get pods

echo ""
if kubectl --namespace kong-system get pods | grep -q "kong-operator.*Running"; then
    print_success "Kong Operator is running"
else
    print_error "Kong Operator is not running. Please install it first (Step 1 in README)."
    exit 1
fi

prompt_continue

# Step 4: Deploy Secret and KonnectAPIAuthConfiguration
print_step "Step 4: Deploying Secret and KonnectAPIAuthConfiguration..."
echo ""

if [ ! -f "konnect-auth.yaml" ]; then
    print_error "konnect-auth.yaml not found!"
    exit 1
fi

envsubst < konnect-auth.yaml | kubectl apply -f -

echo ""
print_info "Waiting for KonnectAPIAuthConfiguration to be valid..."
sleep 5

kubectl get KonnectAPIAuthConfiguration ${CONTROL_PLANE_NAME}-api-auth -n kong

prompt_continue

# Step 5: Choose Control Plane deployment method
print_step "Step 5: Deploying Control Plane"
echo ""
echo "Choose Control Plane deployment method:"
echo "  1) Create a new control plane (managed by Kong Operator)"
echo "  2) Mirror an existing control plane"
echo ""
read -p "Enter your choice [1 or 2]: " CP_CHOICE

if [ "$CP_CHOICE" = "1" ]; then
    # Step 5a: Deploy new Control Plane
    print_info "Deploying new control plane..."
    
    if [ ! -f "control-plane.yaml" ]; then
        print_error "control-plane.yaml not found!"
        exit 1
    fi
    
    envsubst < control-plane.yaml | kubectl apply -f -
    
    print_success "Control plane deployed. Check it in the Konnect UI:"
    print_info "https://cloud.konghq.com/us/gateway-manager/"

elif [ "$CP_CHOICE" = "2" ]; then
    # Step 5b: Mirror existing Control Plane
    print_info "Fetching existing control plane ID..."
    
    CONTROL_PLANE_ID=$(curl -s -X GET "https://${KONNECT_API_ENDPOINT}/v2/control-planes?filter\[name\]=${CONTROL_PLANE_NAME}" \
        -H "Authorization: Bearer ${PAT}" | jq -r '.data[0].id')
    
    if [ -z "$CONTROL_PLANE_ID" ] || [ "$CONTROL_PLANE_ID" = "null" ]; then
        print_error "Could not find control plane with name: $CONTROL_PLANE_NAME"
        exit 1
    fi
    
    export CONTROL_PLANE_ID
    print_success "Found control plane ID: $CONTROL_PLANE_ID"
    
    if [ ! -f "control-plane-mirror.yaml" ]; then
        print_error "control-plane-mirror.yaml not found!"
        exit 1
    fi
    
    envsubst < control-plane-mirror.yaml | kubectl apply -f -
    
    print_success "Control plane mirror deployed"
else
    print_error "Invalid choice. Please enter 1 or 2."
    exit 1
fi

prompt_continue

# Step 6: Deploy Data Plane
print_step "Step 6: Deploying Data Plane..."
echo ""

if [ ! -f "data-plane.yaml" ]; then
    print_error "data-plane.yaml not found!"
    exit 1
fi

print_info "Note: Please review data-plane.yaml for any customizations (e.g., EKS load balancer annotations)"
prompt_continue

envsubst < data-plane.yaml | kubectl apply -f -

print_success "Data plane deployed!"

echo ""
print_info "Waiting for data plane pod to start (this may take a minute)..."
sleep 10

echo ""
print_step "Checking data plane status..."
kubectl get pods -n kong

echo ""
print_success "Setup complete!"
echo ""
echo -e "${GREEN}Next steps:${NC}"
echo "  1. Check your Konnect UI for the data plane connection:"
echo "     https://cloud.konghq.com/us/gateway-manager/"
echo ""
echo "  2. Test availability with:"
echo "     curl http://localhost:$LB_HTTP_PORT/"
echo ""
echo "  3. You can monitor pods with:"
echo "     kubectl get pods -n kong --watch"
echo "     (or use k9s for an interactive view)"
echo ""
print_info "You are now ready to configure services, routes, and plugins!"
