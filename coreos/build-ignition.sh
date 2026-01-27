#!/bin/bash
# Simple script to replace secrets and build Ignition files
# Usage: ./build-ignition.sh [host01|host02|host03|all]

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
NC='\033[0m'

# Help
if [ "$1" = "-h" ] || [ "$1" = "--help" ]; then
  cat <<EOF
${BLUE}Build Ignition Files for CoreOS Nodes${NC}

${GREEN}Usage:${NC}
  ./build-ignition.sh [host01|host02|host03|all]

${GREEN}Examples:${NC}
  ./build-ignition.sh host03           # Bootstrap node only
  ./build-ignition.sh host01           # Join node 1
  ./build-ignition.sh all              # All nodes

${GREEN}Required:${NC}
  secrets.env with:
    - SSH_PUBLIC_KEY
    - PASSWORD_HASH
    - JOIN_TOKEN (for host01, host02)

${GREEN}Output:${NC}
  ignition/<hostname>.ign

EOF
  exit 0
fi

# Load secrets
if [ ! -f "secrets.env" ]; then
  echo -e "${RED}❌ Error: secrets.env not found!${NC}"
  echo ""
  echo "Create it from template:"
  echo "  cp secrets.env.example secrets.env"
  echo "  nano secrets.env"
  exit 1
fi

source secrets.env

# Validate required secrets
if [ -z "$SSH_PUBLIC_KEY" ]; then
  echo -e "${RED}❌ Error: SSH_PUBLIC_KEY not set in secrets.env${NC}"
  exit 1
fi

if [ -z "$PASSWORD_HASH" ]; then
  echo -e "${RED}❌ Error: PASSWORD_HASH not set in secrets.env${NC}"
  exit 1
fi

# Function to build a single node
build_node() {
  local hostname=$1
  local bu_file=""

  # Determine which config to use
  if [ "$hostname" = "host03" ]; then
    # host03: bootstrap if no token, join if token exists
    if [ -z "$JOIN_TOKEN" ]; then
      bu_file="fcos-host03-bootstrap.bu"
      echo -e "${BLUE}Building $hostname (bootstrap mode)...${NC}"
    else
      bu_file="fcos-host03-join.bu"
      echo -e "${BLUE}Building $hostname (join mode)...${NC}"
    fi
  else
    # host01, host02: always join
    bu_file="fcos-${hostname}-join.bu"
    if [ -z "$JOIN_TOKEN" ]; then
      echo -e "${RED}❌ Error: JOIN_TOKEN required for $hostname${NC}"
      echo "Get token from host03: ssh core@10.0.100.103 'sudo cat /var/lib/rancher/rke2/server/node-token'"
      return 1
    fi
    echo -e "${BLUE}Building $hostname...${NC}"
  fi

  if [ ! -f "$bu_file" ]; then
    echo -e "${RED}❌ Error: $bu_file not found!${NC}"
    return 1
  fi

  # Create temp file with secrets replaced
  local temp_bu=$(mktemp)

  sed -e "s|{{SSH_PUBLIC_KEY}}|${SSH_PUBLIC_KEY}|g" \
      -e "s|{{PASSWORD_HASH}}|${PASSWORD_HASH}|g" \
      -e "s|{{JOIN_TOKEN}}|${JOIN_TOKEN}|g" \
      "$bu_file" > "$temp_bu"

  # Convert to Ignition
  mkdir -p ignition
  butane --strict --pretty "$temp_bu" > "ignition/${hostname}.ign"

  rm "$temp_bu"

  echo -e "${GREEN}✓${NC} ignition/${hostname}.ign"
}

# Determine which hosts to build
if [ -z "$1" ] || [ "$1" = "all" ]; then
  HOSTS=("host03" "host01" "host02")
else
  HOSTS=("$1")
fi

# Build nodes
echo ""
SUCCESS=0
FAILED=0

for host in "${HOSTS[@]}"; do
  if build_node "$host"; then
    ((SUCCESS++))
  else
    ((FAILED++))
  fi
done

echo ""
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"

if [ $FAILED -eq 0 ]; then
  echo -e "${GREEN}✅ Built $SUCCESS Ignition file(s) successfully!${NC}"
  echo ""
  echo "Files:"
  ls -1 ignition/*.ign
  echo ""
  echo -e "${BLUE}Next: Write to USB${NC}"
  echo "  sudo coreos-installer install /dev/sdX \\"
  echo "    --image-file fedora-coreos.iso \\"
  echo "    --ignition-file ignition/host03.ign"
else
  echo -e "${RED}⚠️  $SUCCESS succeeded, $FAILED failed${NC}"
  exit 1
fi
