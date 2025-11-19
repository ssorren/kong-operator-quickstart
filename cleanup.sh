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

print_warning() {
    echo -e "${RED}⚠ $1${NC}"
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
echo -e "${RED}================================${NC}"
echo -e "${RED}Kong Operator Cleanup Script${NC}"
echo -e "${RED}================================${NC}"
echo ""
print_warning "This script will DELETE Kong resources from your cluster!"
echo ""

# Check prerequisites
print_step "Checking prerequisites..."
missing_deps=()
for cmd in kubectl; do
    if command_exists "$cmd"; then
        print_success "$cmd found"
    else
        print_error "$cmd not found"
        missing_deps+=("$cmd")
    fi
done

if [ ${#missing_deps[@]} -ne 0 ]; then
    print_error "Missing required dependencies: ${missing_deps[*]}"
    exit 1
fi

prompt_continue

# Get Control Plane Name
print_step "Identifying resources to delete"
echo ""

read -p "Enter CONTROL_PLANE_NAME [default: ko-quickstart]: " CONTROL_PLANE_NAME
CONTROL_PLANE_NAME=${CONTROL_PLANE_NAME:-ko-quickstart}

echo ""
print_info "The following resources will be deleted:"
echo "  - DataPlane: ${CONTROL_PLANE_NAME}-dataplane"
echo "  - KonnectExtension: ${CONTROL_PLANE_NAME}-extension"
echo "  - KonnectGatewayControlPlane: ${CONTROL_PLANE_NAME}"
echo "  - KonnectAPIAuthConfiguration: ${CONTROL_PLANE_NAME}-api-auth"
echo "  - Secret: ${CONTROL_PLANE_NAME}-secret"
echo ""

print_warning "This action cannot be undone!"
read -p "Are you sure you want to continue? Type 'yes' to confirm: " CONFIRM

if [ "$CONFIRM" != "yes" ]; then
    print_info "Cleanup cancelled."
    exit 0
fi

prompt_continue

# Step 1: Delete Data Plane (reverse of Step 6)
print_step "Step 1/5: Deleting DataPlane..."
echo ""

if kubectl get dataplane ${CONTROL_PLANE_NAME}-dataplane -n kong >/dev/null 2>&1; then
    kubectl delete dataplane ${CONTROL_PLANE_NAME}-dataplane -n kong
    print_success "DataPlane deleted"
else
    print_info "DataPlane not found (may already be deleted)"
fi

echo ""
print_info "Waiting for data plane pods to terminate..."
sleep 5

prompt_continue

# Step 2: Delete KonnectExtension
print_step "Step 2/5: Deleting KonnectExtension..."
echo ""

if kubectl get konnectextension ${CONTROL_PLANE_NAME}-extension -n kong >/dev/null 2>&1; then
    kubectl delete konnectextension ${CONTROL_PLANE_NAME}-extension -n kong
    print_success "KonnectExtension deleted"
else
    print_info "KonnectExtension not found (may already be deleted)"
fi

prompt_continue

# Step 3: Delete Control Plane (reverse of Step 5)
print_step "Step 3/5: Deleting KonnectGatewayControlPlane..."
echo ""

if kubectl get konnectgatewaycontrolplane ${CONTROL_PLANE_NAME} -n kong >/dev/null 2>&1; then
    kubectl delete konnectgatewaycontrolplane ${CONTROL_PLANE_NAME} -n kong
    print_success "KonnectGatewayControlPlane deleted"
else
    print_info "KonnectGatewayControlPlane not found (may already be deleted)"
fi

echo ""
print_info "Note: If you used a mirrored control plane, the control plane in Konnect UI will remain."
print_info "If you used a managed control plane, it will be removed from Konnect UI as well."

prompt_continue

# Step 4: Delete KonnectAPIAuthConfiguration (reverse of Step 4)
print_step "Step 4/5: Deleting KonnectAPIAuthConfiguration..."
echo ""

if kubectl get konnectapiauthconfiguration ${CONTROL_PLANE_NAME}-api-auth -n kong >/dev/null 2>&1; then
    kubectl delete konnectapiauthconfiguration ${CONTROL_PLANE_NAME}-api-auth -n kong
    print_success "KonnectAPIAuthConfiguration deleted"
else
    print_info "KonnectAPIAuthConfiguration not found (may already be deleted)"
fi

prompt_continue

# Step 5: Delete Secret
print_step "Step 5/5: Deleting Secret..."
echo ""

if kubectl get secret ${CONTROL_PLANE_NAME}-secret -n kong >/dev/null 2>&1; then
    kubectl delete secret ${CONTROL_PLANE_NAME}-secret -n kong
    print_success "Secret deleted"
else
    print_info "Secret not found (may already be deleted)"
fi

echo ""
print_success "Cleanup complete!"
echo ""
print_info "Summary of deleted resources for control plane '${CONTROL_PLANE_NAME}':"
echo "  ✓ DataPlane"
echo "  ✓ KonnectGatewayControlPlane"
echo "  ✓ KonnectExtension"
echo "  ✓ KonnectAPIAuthConfiguration"
echo "  ✓ Secret"
echo ""
print_info "Remaining resources you may want to check:"
echo "  - Kong namespace: kubectl get all -n kong"
echo "  - LoadBalancer (if not auto-deleted): kubectl get svc -n kong"
echo ""
print_info "The Kong Operator itself is still running. To remove it:"
echo "  helm uninstall kong-operator -n kong-system"
echo "  kubectl delete namespace kong-system"
echo "  kubectl delete namespace kong"
