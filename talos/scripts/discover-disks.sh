#!/usr/bin/env bash

# Talos Disk Discovery Helper
# Helps identify the correct disks for OS and Longhorn
# Usage: ./discover-disks.sh <node-ip>

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TALOS_DIR="$(dirname "${SCRIPT_DIR}")"
SECRETS_DIR="${TALOS_DIR}/secrets"
TALOSCONFIG="${SECRETS_DIR}/talosconfig"

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

# Usage
usage() {
    echo "Usage: $0 <node-ip>"
    echo ""
    echo "Example:"
    echo "  $0 10.0.100.103"
    exit 1
}

# Convert bytes to human readable
human_readable() {
    local bytes=$1
    if [[ ${bytes} -ge 1099511627776 ]]; then
        echo "$(awk "BEGIN {printf \"%.2f\", ${bytes}/1099511627776}")TB"
    elif [[ ${bytes} -ge 1073741824 ]]; then
        echo "$(awk "BEGIN {printf \"%.2f\", ${bytes}/1073741824}")GB"
    elif [[ ${bytes} -ge 1048576 ]]; then
        echo "$(awk "BEGIN {printf \"%.2f\", ${bytes}/1048576}")MB"
    else
        echo "${bytes}B"
    fi
}

# Main function
main() {
    local node_ip="${1:-}"

    if [[ -z "${node_ip}" ]]; then
        usage
    fi

    log_info "Talos Disk Discovery"
    log_info "===================="
    log_info ""
    log_info "Discovering disks on node: ${node_ip}"
    log_info ""

    # Check if talosctl is available
    if ! command -v talosctl &> /dev/null; then
        log_error "talosctl not found. Please install it first."
        exit 1
    fi

    # Check if talosconfig exists
    if [[ ! -f "${TALOSCONFIG}" ]]; then
        log_error "talosconfig not found at: ${TALOSCONFIG}"
        log_error "You can still use talosctl with --insecure flag:"
        log_error "  talosctl --insecure --nodes ${node_ip} disks"
        exit 1
    fi

    # Get disk info
    log_info "Fetching disk information..."
    echo ""

    local disks_json
    if [[ -f "${TALOSCONFIG}" ]]; then
        disks_json=$(talosctl --talosconfig "${TALOSCONFIG}" --nodes "${node_ip}" get disks -o json 2>/dev/null || echo "[]")
    else
        disks_json=$(talosctl --insecure --nodes "${node_ip}" get disks -o json 2>/dev/null || echo "[]")
    fi

    if [[ "${disks_json}" == "[]" ]]; then
        log_warn "Could not retrieve disk information via Talos API"
        log_info "Trying alternative method..."
        echo ""

        if [[ -f "${TALOSCONFIG}" ]]; then
            talosctl --talosconfig "${TALOSCONFIG}" --nodes "${node_ip}" read /proc/partitions
        else
            talosctl --insecure --nodes "${node_ip}" read /proc/partitions
        fi

        echo ""
        log_info "Run lsblk for more details:"
        if [[ -f "${TALOSCONFIG}" ]]; then
            talosctl --talosconfig "${TALOSCONFIG}" --nodes "${node_ip}" ls /dev/disk/by-id/
        else
            talosctl --insecure --nodes "${node_ip}" ls /dev/disk/by-id/
        fi

        exit 0
    fi

    # Parse and display disk info
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    printf "%-30s %-10s %-10s %-10s\n" "Device" "Size" "Type" "Model"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

    # This is a simplified display - actual parsing would depend on talosctl output format
    if [[ -f "${TALOSCONFIG}" ]]; then
        talosctl --talosconfig "${TALOSCONFIG}" --nodes "${node_ip}" disks
    else
        talosctl --insecure --nodes "${node_ip}" disks
    fi

    echo ""
    log_info "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    log_info "Disk Selection Recommendations:"
    log_info "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""
    echo "For OS Disk (Talos installation):"
    echo "  - Size: 200-600GB NVMe"
    echo "  - Use diskSelector in machine config (size in BYTES!):"
    echo "    diskSelector:"
    echo "      size: '<= 644245094400'  # 600GB in bytes"
    echo "      type: nvme"
    echo "  - Or specify exact disk path (more reliable):"
    echo "    disk: /dev/nvme0n1  # Check with 'ls /dev/disk/by-id/'"
    echo ""
    echo "For Longhorn Storage:"
    echo "  - Size: 2TB+ NVMe (larger disk)"
    echo "  - Will be configured via Longhorn after bootstrap"
    echo "  - Longhorn will auto-detect available disks"
    echo ""
    echo "Common Disk Sizes in Bytes:"
    echo "  - 256GB  = 274877906944"
    echo "  - 512GB  = 549755813888"
    echo "  - 600GB  = 644245094400"
    echo "  - 1TB    = 1099511627776"
    echo "  - 2TB    = 2199023255552"
    echo ""
    log_info "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""
    log_info "To see detailed disk information by ID:"
    if [[ -f "${TALOSCONFIG}" ]]; then
        echo "  talosctl --talosconfig ${TALOSCONFIG} --nodes ${node_ip} ls /dev/disk/by-id/"
    else
        echo "  talosctl --insecure --nodes ${node_ip} ls /dev/disk/by-id/"
    fi
    echo ""
    log_info "To see partition layout:"
    if [[ -f "${TALOSCONFIG}" ]]; then
        echo "  talosctl --talosconfig ${TALOSCONFIG} --nodes ${node_ip} read /proc/partitions"
    else
        echo "  talosctl --insecure --nodes ${node_ip} read /proc/partitions"
    fi
}

main "$@"
