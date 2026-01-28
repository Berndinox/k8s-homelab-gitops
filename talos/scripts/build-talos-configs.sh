#!/usr/bin/env bash

# Talos Configuration Builder
# Generates Talos machine configs for homelab cluster
# Usage: ./build-talos-configs.sh [host01|host02|host03|all]

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TALOS_DIR="$(dirname "${SCRIPT_DIR}")"
CONFIGS_DIR="${TALOS_DIR}/configs"
SECRETS_DIR="${TALOS_DIR}/secrets"
MANIFESTS_DIR="${TALOS_DIR}/manifests"
SECRETS_FILE="${TALOS_DIR}/secrets.env"

# Talos version (latest stable)
TALOS_VERSION="v1.12.1"

# Color output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
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

# Check if talosctl is installed
check_talosctl() {
    if ! command -v talosctl &> /dev/null; then
        log_error "talosctl not found. Please install it first:"
        echo "  https://www.talos.dev/latest/introduction/getting-started/"
        echo ""
        echo "  On Linux:"
        echo "    curl -sL https://talos.dev/install | sh"
        echo ""
        echo "  On macOS:"
        echo "    brew install siderolabs/tap/talosctl"
        exit 1
    fi
    log_info "talosctl version: $(talosctl version --client --short)"
}

# Load secrets
load_secrets() {
    if [[ ! -f "${SECRETS_FILE}" ]]; then
        log_error "secrets.env not found!"
        log_error "Please copy secrets.env.example to secrets.env and fill in your values"
        exit 1
    fi

    log_info "Loading secrets from ${SECRETS_FILE}"
    # Source the file but export all variables
    set -a
    source "${SECRETS_FILE}"
    set +a

    # Validate required variables
    if [[ -z "${VIP_ADDRESS:-}" ]]; then
        log_error "VIP_ADDRESS not set in secrets.env"
        exit 1
    fi

    if [[ -z "${SSH_PUBLIC_KEY:-}" ]]; then
        log_warn "SSH_PUBLIC_KEY not set - SSH access will not be configured"
    fi

    # Set defaults
    DNS_SERVERS="${DNS_SERVERS:-8.8.8.8,8.8.4.4}"
    NTP_SERVERS="${NTP_SERVERS:-pool.ntp.org}"
    GITOPS_REPO="${GITOPS_REPO:-}"
    GITOPS_BRANCH="${GITOPS_BRANCH:-main}"
}

# Generate Talos secrets if not exists
generate_secrets() {
    mkdir -p "${SECRETS_DIR}"

    if [[ ! -f "${SECRETS_DIR}/secrets.yaml" ]]; then
        log_info "Generating new Talos secrets..."
        talosctl gen secrets -o "${SECRETS_DIR}/secrets.yaml"
        log_info "Secrets generated: ${SECRETS_DIR}/secrets.yaml"
    else
        log_info "Using existing Talos secrets: ${SECRETS_DIR}/secrets.yaml"
    fi
}

# Generate inline manifests for bootstrap
generate_inline_manifests() {
    log_info "Generating inline manifests (Cilium, ArgoCD, Root App)..."

    # Run the generate script
    bash "${SCRIPT_DIR}/generate-inline-manifests.sh"

    # Verify manifests exist
    if [[ ! -f "${MANIFESTS_DIR}/cilium-inline.yaml" ]] || \
       [[ ! -f "${MANIFESTS_DIR}/argocd-inline.yaml" ]] || \
       [[ ! -f "${MANIFESTS_DIR}/root-app-inline.yaml" ]]; then
        log_error "Failed to generate inline manifests"
        exit 1
    fi

    log_info "✓ Inline manifests generated successfully"
}

# Helper function to indent YAML content for inline manifests
# Adds 8 spaces to each line (for inline manifest contents)
indent_manifest() {
    local manifest_file="$1"
    sed 's/^/        /' "${manifest_file}"
}

# Replace template variables in a file
replace_variables() {
    local input_file="$1"
    local output_file="$2"
    local hostname="$3"
    local node_ip="$4"

    log_info "Processing template: ${input_file} -> ${output_file}"

    # Create temp file
    local temp_file=$(mktemp)

    # Copy template
    cp "${input_file}" "${temp_file}"

    # Replace simple variables
    sed -i "s|{{TALOS_VERSION}}|${TALOS_VERSION}|g" "${temp_file}"
    sed -i "s|{{HOSTNAME}}|${hostname}|g" "${temp_file}"
    sed -i "s|{{NODE_IP}}|${node_ip}|g" "${temp_file}"
    sed -i "s|{{VIP_ADDRESS}}|${VIP_ADDRESS}|g" "${temp_file}"

    # Convert DNS_SERVERS (comma-separated) to YAML array
    local dns_array=""
    IFS=',' read -ra DNS_ARRAY <<< "${DNS_SERVERS}"
    for dns in "${DNS_ARRAY[@]}"; do
        dns=$(echo "$dns" | xargs)  # Trim whitespace
        dns_array="${dns_array}      - ${dns}\n"
    done
    # Remove trailing newline
    dns_array=$(echo -e "${dns_array}" | sed '$ d')
    # Replace placeholder (using @ as delimiter because of slashes in sed)
    sed -i "s@{{DNS_SERVERS_ARRAY}}@${dns_array}@g" "${temp_file}"

    # Convert NTP_SERVERS (comma-separated) to YAML array
    local ntp_array=""
    IFS=',' read -ra NTP_ARRAY <<< "${NTP_SERVERS}"
    for ntp in "${NTP_ARRAY[@]}"; do
        ntp=$(echo "$ntp" | xargs)  # Trim whitespace
        ntp_array="${ntp_array}      - ${ntp}\n"
    done
    # Remove trailing newline
    ntp_array=$(echo -e "${ntp_array}" | sed '$ d')
    # Replace placeholder
    sed -i "s@{{NTP_SERVERS_ARRAY}}@${ntp_array}@g" "${temp_file}"

    # Replace inline manifest placeholders (only for controlplane)
    if [[ "${input_file}" == *"controlplane"* ]]; then
        log_info "  Embedding inline manifests..."

        # Create temporary files with indented manifests
        local cilium_indented=$(mktemp)
        local argocd_indented=$(mktemp)
        local rootapp_indented=$(mktemp)

        indent_manifest "${MANIFESTS_DIR}/cilium-inline.yaml" > "${cilium_indented}"
        indent_manifest "${MANIFESTS_DIR}/argocd-inline.yaml" > "${argocd_indented}"
        indent_manifest "${MANIFESTS_DIR}/root-app-inline.yaml" > "${rootapp_indented}"

        # Use awk to replace multi-line placeholders
        # This is more reliable than sed for large multi-line replacements
        awk -v cilium="$(cat "${cilium_indented}")" \
            '{gsub(/{{CILIUM_INLINE_MANIFEST}}/, cilium)}1' "${temp_file}" > "${temp_file}.tmp"
        mv "${temp_file}.tmp" "${temp_file}"

        awk -v argocd="$(cat "${argocd_indented}")" \
            '{gsub(/{{ARGOCD_INLINE_MANIFEST}}/, argocd)}1' "${temp_file}" > "${temp_file}.tmp"
        mv "${temp_file}.tmp" "${temp_file}"

        awk -v rootapp="$(cat "${rootapp_indented}")" \
            '{gsub(/{{ROOT_APP_INLINE_MANIFEST}}/, rootapp)}1' "${temp_file}" > "${temp_file}.tmp"
        mv "${temp_file}.tmp" "${temp_file}"

        # Cleanup
        rm -f "${cilium_indented}" "${argocd_indented}" "${rootapp_indented}"

        log_info "  ✓ Inline manifests embedded"
    fi

    # Move to output
    mv "${temp_file}" "${output_file}"
}

# Generate config for a specific host
generate_host_config() {
    local host="$1"
    local node_ip=""
    local machine_type="controlplane"  # All nodes are controlplane

    case "${host}" in
        host01)
            node_ip="10.0.100.101"
            ;;
        host02)
            node_ip="10.0.100.102"
            ;;
        host03)
            node_ip="10.0.100.103"
            ;;
        *)
            log_error "Unknown host: ${host}"
            exit 1
            ;;
    esac

    log_info "Generating configuration for ${host} (${machine_type}, IP: ${node_ip})"

    # Create merged config file
    local merged_config="${CONFIGS_DIR}/${host}-merged.yaml"
    local base_patch="${CONFIGS_DIR}/base-patch.yaml"
    local host_patch="${CONFIGS_DIR}/${machine_type}-${host}.yaml"

    # Process base patch
    replace_variables \
        "${CONFIGS_DIR}/base-patch.yaml.template" \
        "${base_patch}" \
        "${host}" \
        "${node_ip}"

    # Process host-specific patch
    replace_variables \
        "${CONFIGS_DIR}/${machine_type}-${host}.yaml.template" \
        "${host_patch}" \
        "${host}" \
        "${node_ip}"

    # Generate final config using talosctl
    log_info "Generating final machine config for ${host}..."

    talosctl gen config homelab "https://${VIP_ADDRESS}:6443" \
        --with-secrets "${SECRETS_DIR}/secrets.yaml" \
        --output "${CONFIGS_DIR}" \
        --output-types "${machine_type}" \
        --force

    # Rename generated file
    if [[ "${machine_type}" == "controlplane" ]]; then
        mv "${CONFIGS_DIR}/controlplane.yaml" "${CONFIGS_DIR}/${host}.yaml"
    else
        mv "${CONFIGS_DIR}/worker.yaml" "${CONFIGS_DIR}/${host}.yaml"
    fi

    # Merge with patches
    log_info "Applying patches to ${host} config..."

    # Create a combined patch file
    cat "${base_patch}" "${host_patch}" > "${merged_config}"

    # Apply patch (this will merge the configs)
    talosctl machineconfig patch "${CONFIGS_DIR}/${host}.yaml" \
        --patch @"${merged_config}" \
        --output "${CONFIGS_DIR}/${host}.yaml"

    # Cleanup temporary files
    rm -f "${base_patch}" "${host_patch}" "${merged_config}"

    log_info "✓ Configuration generated: ${CONFIGS_DIR}/${host}.yaml"
}

# Generate talosconfig
generate_talosconfig() {
    local talosconfig_file="${SECRETS_DIR}/talosconfig"

    if [[ ! -f "${talosconfig_file}" ]]; then
        log_info "Generating talosconfig..."

        talosctl gen config homelab "https://${VIP_ADDRESS}:6443" \
            --with-secrets "${SECRETS_DIR}/secrets.yaml" \
            --output-types talosconfig \
            --output "${SECRETS_DIR}" \
            --force

        log_info "✓ talosconfig generated: ${talosconfig_file}"
        log_info ""
        log_info "To use this config, run:"
        log_info "  export TALOSCONFIG=${talosconfig_file}"
    else
        log_info "Using existing talosconfig: ${talosconfig_file}"
    fi
}

# Main function
main() {
    local target="${1:-all}"

    log_info "Talos Configuration Builder"
    log_info "============================"
    log_info ""

    check_talosctl
    load_secrets
    generate_secrets
    generate_inline_manifests
    generate_talosconfig

    log_info ""
    log_info "Building configurations for: ${target}"
    log_info ""

    case "${target}" in
        host01|host02|host03)
            generate_host_config "${target}"
            ;;
        all)
            generate_host_config "host03"
            generate_host_config "host01"
            generate_host_config "host02"
            ;;
        *)
            log_error "Invalid target: ${target}"
            log_error "Usage: $0 [host01|host02|host03|all]"
            exit 1
            ;;
    esac

    log_info ""
    log_info "✓ All configurations generated successfully!"
    log_info ""
    log_info "Inline manifests embedded in controlplane config:"
    log_info "  • Cilium CNI (full featured)"
    log_info "  • ArgoCD GitOps operator"
    log_info "  • Root-of-roots application"
    log_info ""
    log_info "Next steps:"
    log_info "  1. Review generated configs in: ${CONFIGS_DIR}/"
    log_info "  2. Create bootable USB with Talos:"
    log_info "     Download: https://github.com/siderolabs/talos/releases/download/${TALOS_VERSION}/metal-amd64.iso"
    log_info "     Write with Rufus (Windows) or dd (Linux/macOS)"
    log_info "  3. Boot host03 from USB and apply config:"
    log_info "     talosctl apply-config --insecure --nodes 10.0.100.103 --file ${CONFIGS_DIR}/host03.yaml"
    log_info "  4. Bootstrap Kubernetes on host03:"
    log_info "     talosctl bootstrap --nodes 10.0.100.103 --endpoints 10.0.100.103 --talosconfig ${SECRETS_DIR}/talosconfig"
    log_info "  5. Wait for cluster to become ready (~3-5 min):"
    log_info "     talosctl kubeconfig --nodes ${VIP_ADDRESS} --endpoints ${VIP_ADDRESS} --talosconfig ${SECRETS_DIR}/talosconfig"
    log_info "     kubectl get nodes -w"
    log_info "  6. Wait for Cilium and ArgoCD to deploy (automatic via inline manifests):"
    log_info "     kubectl wait --for=condition=ready pod -l app.kubernetes.io/name=cilium -n kube-system --timeout=5m"
    log_info "     kubectl wait --for=condition=ready pod -l app.kubernetes.io/name=argocd-server -n argocd --timeout=5m"
    log_info "  7. Verify infrastructure deployment via ArgoCD:"
    log_info "     kubectl get applications -n argocd"
    log_info "  8. Join host01 and host02 to cluster:"
    log_info "     talosctl apply-config --insecure --nodes 10.0.100.101 --file ${CONFIGS_DIR}/host01.yaml"
    log_info "     talosctl apply-config --insecure --nodes 10.0.100.102 --file ${CONFIGS_DIR}/host02.yaml"
    log_info ""
    log_info "That's it! Cilium, ArgoCD, and all infrastructure will deploy automatically."
}

main "$@"
