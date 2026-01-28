#!/usr/bin/env bash
# Generate inline manifests for Talos bootstrap
# This creates Cilium and ArgoCD YAML that will be embedded in Talos machine config

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
MANIFESTS_DIR="${SCRIPT_DIR}/../manifests"

echo "=== Generating Inline Manifests for Talos Bootstrap ==="
echo ""

# Ensure manifests directory exists
mkdir -p "${MANIFESTS_DIR}"

# ============================================================================
# 1. Generate Cilium YAML from Helm
# ============================================================================
echo "Generating Cilium manifest from Helm chart..."

# Add Cilium Helm repo
helm repo add cilium https://helm.cilium.io/ --force-update
helm repo update cilium

# Use the shared cilium-values.yaml file (same for inline and ArgoCD)
CILIUM_VALUES_FILE="${PROJECT_ROOT}/infrastructure/00-cilium/cilium-values.yaml"

if [[ ! -f "${CILIUM_VALUES_FILE}" ]]; then
    echo "ERROR: Cilium values file not found: ${CILIUM_VALUES_FILE}"
    exit 1
fi

# Generate Cilium YAML with values file
# This ensures inline manifest matches ArgoCD configuration exactly
helm template cilium cilium/cilium \
  --version 1.18.6 \
  --namespace kube-system \
  --values "${CILIUM_VALUES_FILE}" \
  > "${MANIFESTS_DIR}/cilium-inline.yaml"

echo "✓ Cilium manifest generated: ${MANIFESTS_DIR}/cilium-inline.yaml"
echo "  Using values from: ${CILIUM_VALUES_FILE}"
echo ""

# ============================================================================
# 2. Generate ArgoCD YAML
# ============================================================================
echo "Generating ArgoCD manifest..."

# Add ArgoCD Helm repo
helm repo add argo https://argoproj.github.io/argo-helm --force-update
helm repo update argo

# Generate ArgoCD YAML with standard configuration
helm template argocd argo/argo-cd \
  --version 7.7.11 \
  --namespace argocd \
  --create-namespace \
  --set server.service.type=LoadBalancer \
  --set configs.params."server\.insecure"=true \
  --set server.extraArgs[0]="--insecure" \
  > "${MANIFESTS_DIR}/argocd-inline.yaml"

echo "✓ ArgoCD manifest generated: ${MANIFESTS_DIR}/argocd-inline.yaml"
echo ""

# ============================================================================
# 3. Copy Root-of-Roots App
# ============================================================================
echo "Copying root-app manifest..."

cp "${PROJECT_ROOT}/bootstrap/root-app.yaml" "${MANIFESTS_DIR}/root-app-inline.yaml"

echo "✓ Root app manifest copied: ${MANIFESTS_DIR}/root-app-inline.yaml"
echo ""

# ============================================================================
# Summary
# ============================================================================
echo "=== Summary ==="
echo "Generated inline manifests:"
echo "  1. ${MANIFESTS_DIR}/cilium-inline.yaml ($(wc -l < "${MANIFESTS_DIR}/cilium-inline.yaml") lines)"
echo "  2. ${MANIFESTS_DIR}/argocd-inline.yaml ($(wc -l < "${MANIFESTS_DIR}/argocd-inline.yaml") lines)"
echo "  3. ${MANIFESTS_DIR}/root-app-inline.yaml ($(wc -l < "${MANIFESTS_DIR}/root-app-inline.yaml") lines)"
echo ""
echo "These manifests will be embedded into the Talos controlplane configuration"
echo "during the build-talos-configs.sh process."
echo ""
echo "Next step: Run ./scripts/build-talos-configs.sh to generate machine configs"
