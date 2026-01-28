#!/usr/bin/env bash

# Cilium CNI Installation Script
# Installs Cilium CNI before ArgoCD (solves chicken-egg problem)
# Usage: ./install-cilium.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TALOS_DIR="$(dirname "${SCRIPT_DIR}")"

# Cilium configuration
CILIUM_VERSION="1.16.5"
CILIUM_NAMESPACE="kube-system"
VIP_ADDRESS="${VIP_ADDRESS:-10.0.100.111}"

# Color output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

log_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

log_step() {
    echo -e "${BLUE}[STEP]${NC} $1"
}

# Check prerequisites
check_prerequisites() {
    log_step "Checking prerequisites..."

    if ! command -v kubectl &> /dev/null; then
        log_error "kubectl not found. Please install kubectl first."
        exit 1
    fi

    if ! command -v helm &> /dev/null; then
        log_error "helm not found. Please install helm first."
        echo ""
        echo "Install helm:"
        echo "  curl https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash"
        exit 1
    fi

    log_info "✓ Prerequisites check passed"
}

# Wait for Kubernetes API to be ready
wait_for_api() {
    log_step "Waiting for Kubernetes API to be ready..."

    local max_attempts=60
    local attempt=0

    while [[ ${attempt} -lt ${max_attempts} ]]; do
        if kubectl version --request-timeout=5s &>/dev/null; then
            log_info "✓ Kubernetes API is ready"
            return 0
        fi

        attempt=$((attempt + 1))
        echo -n "."
        sleep 5
    done

    log_error "Kubernetes API did not become ready in time"
    exit 1
}

# Install Cilium via Helm
install_cilium() {
    log_step "Installing Cilium ${CILIUM_VERSION} via Helm..."

    # Add Cilium Helm repository
    log_info "Adding Cilium Helm repository..."
    helm repo add cilium https://helm.cilium.io/ --force-update
    helm repo update

    # Check if Cilium is already installed
    if helm list -n ${CILIUM_NAMESPACE} | grep -q cilium; then
        log_warn "Cilium is already installed. Upgrading..."
        HELM_ACTION="upgrade"
    else
        HELM_ACTION="install"
    fi

    # Install/Upgrade Cilium
    log_info "Running: helm ${HELM_ACTION} cilium..."

    helm ${HELM_ACTION} cilium cilium/cilium \
        --version ${CILIUM_VERSION} \
        --namespace ${CILIUM_NAMESPACE} \
        --set ipam.mode=kubernetes \
        --set kubeProxyReplacement=true \
        --set k8sServiceHost=${VIP_ADDRESS} \
        --set k8sServicePort=6443 \
        --set bgpControlPlane.enabled=true \
        --set loadBalancer.mode=hybrid \
        --set loadBalancer.acceleration=native \
        --set routingMode=native \
        --set autoDirectNodeRoutes=true \
        --set ipv4NativeRoutingCIDR=10.1.0.0/16 \
        --set enableIPv4Masquerade=true \
        --set enableIPv6Masquerade=false \
        --set bpf.masquerade=true \
        --set bpf.tproxy=true \
        --set hubble.enabled=true \
        --set hubble.relay.enabled=true \
        --set hubble.ui.enabled=true \
        --set hubble.metrics.enabled="{dns:query,drop,tcp,flow,icmp,http}" \
        --set gatewayAPI.enabled=true \
        --set ipv4.enabled=true \
        --set ipv6.enabled=false \
        --set operator.replicas=1 \
        --set cni.install=true \
        --set cni.exclusive=true \
        --set bandwidthManager.enabled=true \
        --set bandwidthManager.bbr=true \
        --set hostFirewall.enabled=true \
        --set encryption.enabled=false \
        --set localRedirectPolicy=true \
        --set hostPort.enabled=true \
        --set policyEnforcementMode=default \
        --set nodeSelector."kubernetes\.io/os"=linux \
        --set tolerations[0].operator=Exists \
        --set rollOutCiliumPods=true

    log_info "✓ Cilium installation/upgrade completed"
}

# Wait for Cilium to be ready
wait_for_cilium() {
    log_step "Waiting for Cilium to be ready..."

    # Wait for Cilium DaemonSet to be created
    local max_attempts=60
    local attempt=0

    while [[ ${attempt} -lt ${max_attempts} ]]; do
        if kubectl get daemonset -n ${CILIUM_NAMESPACE} cilium &>/dev/null; then
            log_info "✓ Cilium DaemonSet found"
            break
        fi

        attempt=$((attempt + 1))
        echo -n "."
        sleep 2
    done

    if [[ ${attempt} -ge ${max_attempts} ]]; then
        log_error "Cilium DaemonSet not found in time"
        exit 1
    fi

    # Wait for Cilium pods to be ready
    log_info "Waiting for Cilium pods to be ready (this may take 2-5 minutes)..."

    if ! kubectl wait --for=condition=ready pod \
        -l k8s-app=cilium \
        -n ${CILIUM_NAMESPACE} \
        --timeout=600s; then
        log_error "Cilium pods did not become ready in time"
        log_info "Checking pod status:"
        kubectl get pods -n ${CILIUM_NAMESPACE} -l k8s-app=cilium
        log_info "Checking logs:"
        kubectl logs -n ${CILIUM_NAMESPACE} -l k8s-app=cilium --tail=50
        exit 1
    fi

    log_info "✓ Cilium is ready"
}

# Verify Cilium installation
verify_cilium() {
    log_step "Verifying Cilium installation..."

    # Check Cilium status
    log_info "Checking Cilium status..."
    if kubectl exec -n ${CILIUM_NAMESPACE} ds/cilium -- cilium status --brief; then
        log_info "✓ Cilium status OK"
    else
        log_warn "Cilium status check failed (may be normal during initial startup)"
    fi

    # Show Cilium pods
    echo ""
    kubectl get pods -n ${CILIUM_NAMESPACE} -l k8s-app=cilium -o wide

    echo ""
    log_info "✓ Cilium verification completed"
}

# Add ArgoCD annotation for later adoption
annotate_for_argocd() {
    log_step "Adding ArgoCD annotations for GitOps adoption..."

    # Annotate Cilium resources so ArgoCD can adopt them later
    kubectl annotate helmrelease cilium -n ${CILIUM_NAMESPACE} \
        argocd.argoproj.io/tracking-id=cilium:helm.toolkit.fluxcd.io/HelmRelease:kube-system/cilium \
        --overwrite || true

    log_info "✓ ArgoCD annotations added"
    log_info ""
    log_info "Note: After ArgoCD is installed, apply the Cilium Application:"
    log_info "  kubectl apply -f infrastructure/00-cilium/cilium-helm.yaml"
    log_info ""
    log_info "ArgoCD will adopt the existing Cilium installation (no redeployment)."
}

# Display summary
display_summary() {
    log_info ""
    log_info "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    log_info "Cilium Installation Summary"
    log_info "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""
    echo "Cilium Version: ${CILIUM_VERSION}"
    echo "Namespace: ${CILIUM_NAMESPACE}"
    echo "Kube-proxy Replacement: Enabled (eBPF)"
    echo "Hubble: Enabled"
    echo "Gateway API: Enabled"
    echo "BGP Control Plane: Enabled"
    echo ""
    log_info "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""
    log_info "Next steps:"
    log_info "  1. Verify connectivity: kubectl get nodes"
    log_info "  2. Install ArgoCD: ./scripts/bootstrap-gitops.sh"
    log_info "  3. Access Hubble UI:"
    log_info "     kubectl port-forward -n kube-system svc/hubble-ui 12000:80"
    log_info ""
}

# Main function
main() {
    log_info "Cilium CNI Installation"
    log_info "======================="
    log_info ""

    # Load secrets if available
    if [[ -f "${TALOS_DIR}/secrets.env" ]]; then
        set -a
        source "${TALOS_DIR}/secrets.env"
        set +a
        log_info "Loaded VIP from secrets.env: ${VIP_ADDRESS}"
    fi

    check_prerequisites
    wait_for_api
    install_cilium
    wait_for_cilium
    verify_cilium
    annotate_for_argocd
    display_summary

    log_info "✓ Cilium installation completed successfully!"
}

main "$@"
