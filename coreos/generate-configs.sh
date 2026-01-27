#!/bin/bash
# Generate node-specific Butane configs from template
# Usage: ./generate-configs.sh [host01|host02|host03|all]

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Help text
show_help() {
  cat <<EOF
${BLUE}Fedora CoreOS Butane Config Generator${NC}

${GREEN}Usage:${NC}
  ./generate-configs.sh [OPTIONS] [HOSTS...]

${GREEN}Arguments:${NC}
  host01, host02, host03    Generate config for specific host(s)
  all                       Generate configs for all hosts
  (no arguments)            Smart mode: host03 only (if no token), or all hosts (if token exists)

${GREEN}Examples:${NC}
  ./generate-configs.sh                # Smart mode
  ./generate-configs.sh host03         # Only bootstrap node
  ./generate-configs.sh host01 host02  # Only join nodes
  ./generate-configs.sh all            # All nodes

${GREEN}Options:${NC}
  -h, --help               Show this help message

${GREEN}Required:${NC}
  secrets.env              Must exist with SSH_PUBLIC_KEY and PASSWORD_HASH
                           JOIN_TOKEN required for join nodes (host01, host02)

${GREEN}Output:${NC}
  generated/fcos-<hostname>-*.bu

EOF
}

# Parse options
while [[ $# -gt 0 ]]; do
  case $1 in
    -h|--help)
      show_help
      exit 0
      ;;
    *)
      break
      ;;
  esac
done

# Load secrets from external file (gitignored)
if [ -f "secrets.env" ]; then
  source secrets.env
else
  echo -e "${RED}❌ Error: secrets.env not found!${NC}"
  echo ""
  echo "Create secrets.env from template:"
  echo "  cp secrets.env.example secrets.env"
  echo "  nano secrets.env"
  echo ""
  echo "Required variables:"
  echo "  SSH_PUBLIC_KEY='ssh-rsa AAAA...'"
  echo "  PASSWORD_HASH='\$6\$...'"
  echo "  JOIN_TOKEN='K10...' (only for join nodes)"
  exit 1
fi

# Cluster configuration
CLUSTER_CIDR="10.1.0.0/16"
SERVICE_CIDR="10.2.0.0/16"
BOOTSTRAP_IP="10.0.100.103"

# Node definitions
declare -A NODES
NODES[host01]="10.0.100.101"
NODES[host02]="10.0.100.102"
NODES[host03]="10.0.100.103"

# Determine which hosts to generate
if [ $# -eq 0 ]; then
  # Smart mode
  if [ -z "$JOIN_TOKEN" ]; then
    echo -e "${YELLOW}ℹ️  No JOIN_TOKEN found - generating bootstrap node only${NC}"
    HOSTS_TO_GENERATE=("host03")
  else
    echo -e "${BLUE}ℹ️  JOIN_TOKEN found - generating all nodes${NC}"
    HOSTS_TO_GENERATE=("host01" "host02" "host03")
  fi
elif [ "$1" = "all" ]; then
  HOSTS_TO_GENERATE=("host01" "host02" "host03")
else
  # User specified hosts
  HOSTS_TO_GENERATE=("$@")
fi

# Validate host names
for hostname in "${HOSTS_TO_GENERATE[@]}"; do
  if [[ ! "${!NODES[@]}" =~ "$hostname" ]]; then
    echo -e "${RED}❌ Error: Invalid hostname '${hostname}'${NC}"
    echo "Valid hosts: host01, host02, host03"
    exit 1
  fi
done

# Function to generate RKE2 config (bootstrap)
generate_bootstrap_config() {
  local hostname=$1
  local node_ip=$2

  cat <<EOF
          # Node Configuration
          node-ip: ${node_ip}
          advertise-address: ${node_ip}
          node-name: ${hostname}

          # Network Configuration
          cluster-cidr: ${CLUSTER_CIDR}
          service-cidr: ${SERVICE_CIDR}
          cluster-dns: 10.2.0.10

          # CNI - Use RKE2's bundled Cilium
          cni: cilium

          # Disable unnecessary components
          disable:
            - rke2-ingress-nginx
            - rke2-canal

          # Disable kube-proxy (Cilium will replace it)
          disable-kube-proxy: true
          write-kubeconfig-mode: "0644"

          # TLS SANs for all nodes
          tls-san:
            - host01
            - host02
            - host03
            - 10.0.200.101
            - 10.0.200.102
            - 10.0.200.103
            - 10.0.100.101
            - 10.0.100.102
            - 10.0.100.103

          # Metrics
          etcd-expose-metrics: true
EOF
}

# Function to generate RKE2 config (join)
generate_join_config() {
  local hostname=$1
  local node_ip=$2

  cat <<EOF
          # Join existing cluster
          server: https://${BOOTSTRAP_IP}:9345
          token: ${JOIN_TOKEN}

          # Node Configuration
          node-ip: ${node_ip}
          advertise-address: ${node_ip}
          node-name: ${hostname}

          # Network Configuration
          cluster-cidr: ${CLUSTER_CIDR}
          service-cidr: ${SERVICE_CIDR}
          cluster-dns: 10.2.0.10

          # CNI - Use RKE2's bundled Cilium
          cni: cilium

          # Disable unnecessary components
          disable:
            - rke2-ingress-nginx
            - rke2-canal

          # Disable kube-proxy (Cilium will replace it)
          disable-kube-proxy: true
          write-kubeconfig-mode: "0644"

          # TLS SANs for all nodes
          tls-san:
            - host01
            - host02
            - host03
            - 10.0.200.101
            - 10.0.200.102
            - 10.0.200.103
            - 10.0.100.101
            - 10.0.100.102
            - 10.0.100.103

          # Metrics
          etcd-expose-metrics: true
EOF
}

# Function to generate post-install script (bootstrap)
generate_bootstrap_post_install() {
  cat <<'EOF'
#!/bin/bash
          set -e

          echo "Waiting for RKE2 API to be ready..."
          for i in {1..30}; do
            if /usr/local/bin/kubectl --kubeconfig=/etc/rancher/rke2/rke2.yaml get nodes &>/dev/null; then
              echo "API is ready!"
              break
            fi
            echo "Waiting... ($i/30)"
            sleep 10
          done

          # Setup kubeconfig for core user
          cp /etc/rancher/rke2/rke2.yaml /home/core/.kube/config
          chown -R core:core /home/core/.kube
          chmod 600 /home/core/.kube/config

          # Wait for Cilium helm job
          echo "Waiting for Cilium installation..."
          sleep 30

          # Restart Cilium pods (fix for GitHub Issue #42179)
          echo "Restarting Cilium agents..."
          /usr/local/bin/kubectl --kubeconfig=/etc/rancher/rke2/rke2.yaml \
            delete pods -n kube-system -l k8s-app=cilium --ignore-not-found=true || true

          sleep 10

          echo "Waiting for Cilium to be ready..."
          /usr/local/bin/kubectl --kubeconfig=/etc/rancher/rke2/rke2.yaml \
            wait --for=condition=Ready pods -l k8s-app=cilium -n kube-system --timeout=300s || true

          echo "✅ RKE2 Bootstrap complete!"
          echo ""
          echo "Join token:"
          cat /var/lib/rancher/rke2/server/node-token
EOF
}

# Function to generate post-install script (join)
generate_join_post_install() {
  local hostname=$1

  cat <<EOF
#!/bin/bash
          set -e

          echo "Waiting for RKE2 to join cluster..."
          for i in {1..30}; do
            if /usr/local/bin/kubectl --kubeconfig=/etc/rancher/rke2/rke2.yaml get nodes &>/dev/null; then
              echo "API is ready!"
              break
            fi
            echo "Waiting... (\$i/30)"
            sleep 10
          done

          # Setup kubeconfig for core user
          cp /etc/rancher/rke2/rke2.yaml /home/core/.kube/config
          chown -R core:core /home/core/.kube
          chmod 600 /home/core/.kube/config

          echo "✅ ${hostname} joined cluster!"
EOF
}

# Function to generate a single host config
generate_host_config() {
  local hostname=$1
  local node_ip=${NODES[$hostname]}

  # Determine if bootstrap or join
  if [ "$hostname" = "host03" ]; then
    local config_type="bootstrap"
    local RKE2_CONFIG=$(generate_bootstrap_config "$hostname" "$node_ip")
    local POST_INSTALL=$(generate_bootstrap_post_install)
  else
    # Join node - check if token exists
    if [ -z "$JOIN_TOKEN" ]; then
      echo -e "${RED}❌ Error: JOIN_TOKEN required for $hostname${NC}"
      echo ""
      echo "To generate join nodes:"
      echo "1. Bootstrap host03 first"
      echo "2. Get token: ssh core@${BOOTSTRAP_IP} 'sudo cat /var/lib/rancher/rke2/server/node-token'"
      echo "3. Add to secrets.env: JOIN_TOKEN='<token>'"
      echo "4. Re-run this script"
      return 1
    fi
    local config_type="join"
    local RKE2_CONFIG=$(generate_join_config "$hostname" "$node_ip")
    local POST_INSTALL=$(generate_join_post_install "$hostname")
  fi

  # Generate config from template
  local output_file="generated/fcos-${hostname}-${config_type}.bu"

  sed -e "s|{{HOSTNAME}}|${hostname}|g" \
      -e "s|{{NODE_IP}}|${node_ip}|g" \
      -e "s|{{SSH_PUBLIC_KEY}}|${SSH_PUBLIC_KEY}|g" \
      -e "s|{{PASSWORD_HASH}}|${PASSWORD_HASH}|g" \
      -e "s|{{RKE2_CONFIG}}|${RKE2_CONFIG}|g" \
      -e "s|{{POST_INSTALL_SCRIPT}}|${POST_INSTALL}|g" \
      fcos-template.bu > "$output_file"

  echo -e "${GREEN}✓${NC} Generated: $output_file"
}

# Create output directory
mkdir -p generated

echo -e "${BLUE}🔧 Generating Butane configs from template...${NC}"
echo ""

# Generate configs
SUCCESS=0
FAILED=0

for hostname in "${HOSTS_TO_GENERATE[@]}"; do
  if generate_host_config "$hostname"; then
    ((SUCCESS++))
  else
    ((FAILED++))
  fi
done

echo ""
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"

if [ $FAILED -eq 0 ]; then
  echo -e "${GREEN}✅ All configs generated successfully!${NC}"
  echo ""
  echo "Generated $SUCCESS file(s) in generated/ directory:"
  ls -1 generated/
  echo ""
  echo -e "${BLUE}Next steps:${NC}"
  echo "1. Convert to Ignition:"
  echo "   ${GREEN}butane --strict --pretty generated/fcos-host03-bootstrap.bu > host03.ign${NC}"
  echo ""
  echo "2. Create USB:"
  echo "   ${GREEN}sudo coreos-installer install /dev/sdX --image-file fcos.iso --ignition-file host03.ign${NC}"
else
  echo -e "${RED}⚠️  $SUCCESS succeeded, $FAILED failed${NC}"
  exit 1
fi
