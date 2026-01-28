#!/usr/bin/env bash

# Talos GitOps Bootstrap Script
# Installs ArgoCD and bootstraps GitOps infrastructure
# Usage: ./bootstrap-gitops.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TALOS_DIR="$(dirname "${SCRIPT_DIR}")"
SECRETS_DIR="${TALOS_DIR}/secrets"
TALOSCONFIG="${SECRETS_DIR}/talosconfig"

# GitOps configuration
ARGOCD_VERSION="v2.13.2"  # Latest stable
ARGOCD_NAMESPACE="argocd"
GITOPS_REPO="${GITOPS_REPO:-}"
GITOPS_BRANCH="${GITOPS_BRANCH:-main}"

# VIP Address for API server
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

    if ! command -v talosctl &> /dev/null; then
        log_error "talosctl not found. Please install talosctl first."
        exit 1
    fi

    if [[ ! -f "${TALOSCONFIG}" ]]; then
        log_error "talosconfig not found at: ${TALOSCONFIG}"
        log_error "Please generate configs first: ./build-talos-configs.sh"
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
        if kubectl --server="https://${VIP_ADDRESS}:6443" get nodes &>/dev/null; then
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

# Check if Cilium is ready (must be installed first!)
check_cilium() {
    log_step "Checking if Cilium CNI is ready..."

    # Check if Cilium exists
    if ! kubectl get daemonset -n kube-system cilium &>/dev/null; then
        log_error "Cilium DaemonSet not found!"
        log_error ""
        log_error "Cilium must be installed BEFORE running this script."
        log_error "Please run: ./scripts/install-cilium.sh"
        log_error ""
        exit 1
    fi

    log_info "✓ Cilium DaemonSet found"

    # Wait for cilium pods to be ready
    log_info "Waiting for Cilium pods to be ready..."
    if ! kubectl wait --for=condition=ready pod \
        -l k8s-app=cilium \
        -n kube-system \
        --timeout=120s; then
        log_error "Cilium pods are not ready"
        log_error "Check Cilium status with: kubectl get pods -n kube-system -l k8s-app=cilium"
        exit 1
    fi

    log_info "✓ Cilium CNI is ready"
}

# Install ArgoCD
install_argocd() {
    log_step "Installing ArgoCD ${ARGOCD_VERSION}..."

    # Create namespace
    kubectl create namespace "${ARGOCD_NAMESPACE}" --dry-run=client -o yaml | kubectl apply -f -

    # Install ArgoCD
    kubectl apply -n "${ARGOCD_NAMESPACE}" -f "https://raw.githubusercontent.com/argoproj/argo-cd/${ARGOCD_VERSION}/manifests/install.yaml"

    log_info "✓ ArgoCD manifests applied"

    # Wait for ArgoCD to be ready
    log_info "Waiting for ArgoCD to be ready..."
    kubectl wait --for=condition=ready pod \
        -l app.kubernetes.io/name=argocd-server \
        -n "${ARGOCD_NAMESPACE}" \
        --timeout=600s || {
        log_error "ArgoCD did not become ready in time"
        exit 1
    }

    log_info "✓ ArgoCD is ready"

    # Get initial admin password
    local admin_password=$(kubectl -n "${ARGOCD_NAMESPACE}" get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d)

    log_info ""
    log_info "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    log_info "ArgoCD Admin Credentials:"
    log_info "  Username: admin"
    log_info "  Password: ${admin_password}"
    log_info ""
    log_info "Access ArgoCD UI via port-forward:"
    log_info "  kubectl port-forward svc/argocd-server -n argocd 8080:443"
    log_info "  Open: https://localhost:8080"
    log_info "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    log_info ""
}

# Bootstrap GitOps
bootstrap_gitops() {
    log_step "Bootstrapping GitOps infrastructure..."

    # Check if GitOps repo is configured
    if [[ -z "${GITOPS_REPO}" ]]; then
        log_warn "GITOPS_REPO not set in secrets.env"
        log_warn "Skipping GitOps bootstrap - you'll need to manually create the root app"
        return 0
    fi

    # Create root application
    cat <<EOF | kubectl apply -f -
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: root-app
  namespace: ${ARGOCD_NAMESPACE}
  finalizers:
    - resources-finalizer.argocd.argoproj.io
spec:
  project: default
  source:
    repoURL: ${GITOPS_REPO}
    targetRevision: ${GITOPS_BRANCH}
    path: bootstrap
  destination:
    server: https://kubernetes.default.svc
    namespace: ${ARGOCD_NAMESPACE}
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
      allowEmpty: false
    syncOptions:
      - CreateNamespace=true
EOF

    log_info "✓ Root application created"

    # Wait for infrastructure app to sync
    log_info "Waiting for infrastructure application to sync..."
    kubectl wait --for=jsonpath='{.status.health.status}'=Healthy \
        application/infrastructure \
        -n "${ARGOCD_NAMESPACE}" \
        --timeout=600s || {
        log_warn "Infrastructure application did not become healthy in time"
        log_warn "Check ArgoCD UI for details"
    }

    log_info "✓ GitOps infrastructure bootstrapped"
}

# Display cluster info
display_cluster_info() {
    log_info ""
    log_info "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    log_info "Cluster Information:"
    log_info "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

    echo ""
    kubectl get nodes -o wide

    echo ""
    log_info "Pod Network CIDR: 10.1.0.0/16"
    log_info "Service Network CIDR: 10.2.0.0/16"
    log_info "VIP Address: ${VIP_ADDRESS}"

    echo ""
    log_info "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
}

# Main function
main() {
    log_info "Talos GitOps Bootstrap"
    log_info "======================"
    log_info ""

    # Load secrets if available
    if [[ -f "${TALOS_DIR}/secrets.env" ]]; then
        set -a
        source "${TALOS_DIR}/secrets.env"
        set +a
    fi

    check_prerequisites
    wait_for_api
    check_cilium
    install_argocd
    bootstrap_gitops
    display_cluster_info

    log_info ""
    log_info "✓ Bootstrap completed successfully!"
    log_info ""
    log_info "Next steps:"
    log_info "  1. Access ArgoCD UI and verify all applications are synced"
    log_info "  2. Join worker nodes (host01, host02) to the cluster"
    log_info "  3. Verify Cilium, Longhorn, Multus, and KubeVirt are running"
    log_info "  4. Configure your applications via GitOps"
}

main "$@"
