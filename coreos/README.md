# Fedora CoreOS - RKE2 Kubernetes Cluster

3-node high-availability RKE2 cluster with Cilium CNI and ArgoCD GitOps.

## Architecture

```
3x Control Plane Nodes (Fedora CoreOS)
├── Management: DHCP via eno1
├── Cluster: VLAN 100 (bond0 LACP 20G)
│   ├── host01: 10.0.100.101
│   ├── host02: 10.0.100.102
│   └── host03: 10.0.100.103
├── Pod Network: 10.1.0.0/16 (Cilium)
└── Service Network: 10.2.0.0/16
```

**Stack:**
- RKE2 (Kubernetes)
- Cilium CNI (kube-proxy replacement, BGP, Hubble)
- ArgoCD (GitOps, auto-deployed)
- Longhorn (planned, 3x replica storage)

## Files

```
fcos-host03-bootstrap.bu    # First node (bootstrap cluster)
fcos-host03-join.bu         # host03 join config (for rebuild)
fcos-host01-join.bu         # Join node 1
fcos-host02-join.bu         # Join node 2
build-ignition.sh           # Build Ignition files from templates
secrets.env.example         # Template for secrets
```

---

## Quick Start

> **Note for macOS users:** Use Ventoy (manual download from GitHub) - it works exactly like `coreos-installer` on Linux. One USB stick, ISO + Ignition config, done. One-time setup, then identical workflow to Linux.

### Prerequisites

**Tools:**

**macOS (ARM/Intel):**
```bash
# Install Butane (for building Ignition configs)
brew install butane

# Install Ventoy manually (one-time setup)
# Download from: https://github.com/ventoy/Ventoy/releases/latest
# 1. Download: Ventoy-X.X.XX-mac.tar.gz
# 2. Extract and run VentoyGUI or use CLI
```

**Linux:**
```bash
# Install Butane
curl -L https://github.com/coreos/butane/releases/latest/download/butane-x86_64-unknown-linux-gnu -o /usr/local/bin/butane
chmod +x /usr/local/bin/butane

# Install CoreOS Installer
curl -L https://github.com/coreos/coreos-installer/releases/latest/download/coreos-installer-x86_64-unknown-linux-gnu -o /usr/local/bin/coreos-installer
chmod +x /usr/local/bin/coreos-installer
```

**Download Fedora CoreOS ISO:**

**Linux:**
```bash
coreos-installer download -s stable -p metal -f iso
```

**macOS (direct download):**
```bash
# Get latest stable ISO directly
curl -L -o fedora-coreos-stable.iso \
  'https://builds.coreos.fedoraproject.org/prod/streams/stable/builds/43.20260105.3.0/x86_64/fedora-coreos-43.20260105.3.0-live-iso.x86_64.iso'

# Or check for latest version at:
# https://fedoraproject.org/coreos/download
```

### 1. Create Secrets

```bash
cd coreos/
cp secrets.env.example secrets.env
nano secrets.env
```

Fill in:
```bash
# Generate SSH key: ssh-keygen -t rsa -b 4096
SSH_PUBLIC_KEY='ssh-rsa AAAAB3... your@email.com'

# Generate password: mkpasswd -m sha-512
PASSWORD_HASH='$6$rounds=4096$...'

# Leave empty for now (get after bootstrap)
JOIN_TOKEN=''
```

### 2. Bootstrap First Node (host03)

```bash
# Build Ignition file
./build-ignition.sh host03
```

**Create bootable USB:**

**Linux:**
```bash
sudo coreos-installer install /dev/sdX \
  --image-file fedora-coreos-*.iso \
  --ignition-file ignition/host03.ign
```

**macOS (using Ventoy):**

```bash
# 1. Download and install Ventoy (one-time setup)
# Download from: https://github.com/ventoy/Ventoy/releases/latest
# Extract: tar -xzvf ventoy-X.X.XX-mac.tar.gz
cd ventoy-X.X.XX

# Install Ventoy to USB
diskutil list  # Find your USB device (e.g., /dev/disk4)
sudo sh Ventoy2Disk.sh -i /dev/diskN  # Replace diskN with your USB

# 2. Copy ISO to USB (simple drag & drop)
cp fedora-coreos-stable.iso /Volumes/Ventoy/

# 3. Create Ventoy Ignition config directory
mkdir -p /Volumes/Ventoy/ventoy/

# 4. Copy Ignition config with Ventoy naming convention
cp ignition/host03.ign /Volumes/Ventoy/ventoy/fedora-coreos-stable.ign

# That's it! Boot from USB:
# - Ventoy shows boot menu
# - Select CoreOS ISO
# - Ignition config is automatically applied
# - Installation proceeds with your config
```

**Ventoy Ignition naming:**
- ISO name: `fedora-coreos-stable.iso`
- Ignition: `fedora-coreos-stable.ign` (same name, different extension)
- Ventoy automatically injects the Ignition config at boot

**Pro tip:** You can have multiple ISOs with different Ignition configs:
```bash
# Different configs per host
cp fedora-coreos-stable.iso /Volumes/Ventoy/coreos-host01.iso
cp fedora-coreos-stable.iso /Volumes/Ventoy/coreos-host02.iso
cp fedora-coreos-stable.iso /Volumes/Ventoy/coreos-host03.iso

cp ignition/host01.ign /Volumes/Ventoy/ventoy/coreos-host01.ign
cp ignition/host02.ign /Volumes/Ventoy/ventoy/coreos-host02.ign
cp ignition/host03.ign /Volumes/Ventoy/ventoy/coreos-host03.ign

# Select the right ISO from Ventoy boot menu
```

**Boot the server:**
- Installation takes ~5 minutes

**What happens automatically:**
1. OS installation
2. Network setup (LACP bond + VLAN)
3. RKE2 installation
4. Cilium CNI deployment
5. **ArgoCD installation** 🎯
6. **GitOps bootstrap** (root-app.yaml applied)

### 3. Get Join Token

```bash
# SSH into host03
ssh core@10.0.100.103

# Get join token
sudo cat /var/lib/rancher/rke2/server/node-token
# Example: K10abc123def456...::server:xyz

# Check cluster status
kubectl get nodes
kubectl get pods -A

# ArgoCD should be running!
kubectl get pods -n argocd
```

### 4. Add Token & Build Join Nodes

```bash
# Back on your workstation
cd coreos/
nano secrets.env
# Add: JOIN_TOKEN='K10abc123...'

# Build all Ignition files
./build-ignition.sh all
```

### 5. Install Remaining Nodes

**Linux (coreos-installer):**
```bash
# host01
sudo coreos-installer install /dev/sdX \
  --image-file fedora-coreos-*.iso \
  --ignition-file ignition/host01.ign

# host02
sudo coreos-installer install /dev/sdX \
  --image-file fedora-coreos-*.iso \
  --ignition-file ignition/host02.ign
```

**macOS (Ventoy):**
```bash
# Copy ISO and Ignition files to Ventoy USB
cp fedora-coreos-stable.iso /Volumes/Ventoy/
cp ignition/host01.ign /Volumes/Ventoy/ventoy/fedora-coreos-stable.ign

# For host02, just replace the .ign file:
cp ignition/host02.ign /Volumes/Ventoy/ventoy/fedora-coreos-stable.ign

# Boot from USB, Ventoy auto-applies the Ignition config
```

### 6. Verify Cluster

```bash
ssh core@10.0.100.103

# Check nodes
kubectl get nodes
# Should show: host01, host02, host03 (all Ready)

# Check ArgoCD applications
kubectl get applications -n argocd

# Get ArgoCD password
kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d
```

**Access ArgoCD UI:**
```bash
# Port-forward from any node
kubectl port-forward svc/argocd-server -n argocd 8080:443 --address=0.0.0.0

# Open browser: https://<node-ip>:8080
# Login: admin / <password-from-above>
```

---

## Configuration Details

### Network Setup

**Bond0 (LACP 802.3ad):**
- enp1s0 + enp1s0d1
- 2x 10G = 20G aggregate
- Layer 3+4 hashing

**VLANs:**
- VLAN 100: Cluster network (10.0.100.0/24)
- eno1: Management (DHCP)

### Cilium Configuration

Managed via RKE2 HelmChartConfig in `/var/lib/rancher/rke2/server/manifests/rke2-cilium-config.yaml`

**Features enabled:**
- kube-proxy replacement (eBPF)
- Hubble observability + UI
- BGP Control Plane (enabled, config TBD)
- LoadBalancer (hybrid mode)
- Native routing

**Update Cilium:**
```bash
# SSH to any node
ssh core@10.0.100.103

# Edit config
sudo nano /var/lib/rancher/rke2/server/manifests/rke2-cilium-config.yaml

# RKE2 automatically detects changes and rolls update
# Watch rollout: kubectl rollout status ds/cilium -n kube-system

# IMPORTANT: Update .bu files in Git afterwards!
```

### ArgoCD Bootstrap

**Automatic deployment includes:**
1. ArgoCD installation (via manifest)
2. Root App of Apps ([bootstrap/root-app.yaml](../bootstrap/root-app.yaml))
3. **Infrastructure** (sync wave 0) - Longhorn, Multus, KubeVirt
4. **Apps** (sync wave 10) - Deployed after infrastructure is healthy

**Repository:** https://github.com/Berndinox/k8s-homelab-gitops

**GitOps Structure:**
```
├── argocd-apps/
│   ├── infrastructure.yaml    # Wave 0: Core infrastructure
│   └── apps.yaml              # Wave 10: Applications (waits for infra)
├── infrastructure/
│   ├── 00-namespaces/         # Namespaces
│   ├── 01-longhorn/           # Storage (wave 1)
│   ├── 02-multus/             # Networking (wave 2, after storage)
│   └── 03-kubevirt/           # Virtualization (wave 3, after multus)
├── apps/                      # Your applications
└── bootstrap/
    └── root-app.yaml          # Orchestrates everything
```

**Bootstrap Process:**
1. ArgoCD installs (~3 min)
2. Root app applies
3. Infrastructure deploys sequentially (wave 0, ~10-15 min)
   - Bootstrap script waits for infrastructure to be healthy
4. Apps deploy automatically (wave 10)
5. All changes auto-sync via Git

**Sync Waves ensure:**
- ✅ Longhorn deployed before Multus
- ✅ Multus deployed before KubeVirt
- ✅ Apps only deploy after infrastructure is ready
- ✅ No manual ordering needed

### Adding Components

**Add Infrastructure Component:**
```bash
# Example: Add Longhorn
cd infrastructure/01-longhorn/
# Add Helm Application or manifests
git add .
git commit -m "Add Longhorn storage"
git push

# ArgoCD syncs automatically
# Deploys in wave 1 (after namespaces, before multus)
```

**Add Application:**
```bash
cd apps/
mkdir my-app
# Add manifests
git add .
git commit -m "Add my-app"
git push

# ArgoCD syncs automatically
# Deploys in wave 10 (after infrastructure is healthy)
```

**Monitor Deployment:**
```bash
# Watch all applications
kubectl get applications -n argocd -w

# Check specific app
kubectl describe application infrastructure -n argocd

# View sync status
kubectl get application infrastructure -n argocd -o yaml | grep -A 5 status
```

---

## Maintenance & Operations

### Rebuild a Node

**Example: Rebuild host01**
```bash
# Build fresh Ignition
./build-ignition.sh host01

# Remove from cluster (optional, will auto-remove on reinstall)
kubectl delete node host01

# Reinstall (Linux)
sudo coreos-installer install /dev/sdX \
  --ignition-file ignition/host01.ign

# macOS: Update Ignition on Ventoy USB, boot and reinstall
cp ignition/host01.ign /Volumes/Ventoy/ventoy/fedora-coreos-stable.ign

# Node will auto-join and sync
```

### Rebuild host03 (Bootstrap Node)

If host03 fails and cluster is running on host01+host02:

**Option A - Join as 3rd node:**
```bash
# Use host03-join config instead of bootstrap
./build-ignition.sh host03  # This builds host03-join.bu!

# Linux
sudo coreos-installer install /dev/sdX --ignition-file ignition/host03.ign

# macOS: Update Ignition on Ventoy USB
cp ignition/host03.ign /Volumes/Ventoy/ventoy/fedora-coreos-stable.ign
```

**Option B - Fresh bootstrap (if entire cluster is lost):**
```bash
# Wipe all nodes, start over with host03-bootstrap
./build-ignition.sh host03
# Use fcos-host03-bootstrap.bu and create bootable USB
```

### Update Node Configuration

Edit the specific `.bu` file:
```bash
nano fcos-host01-join.bu
./build-ignition.sh host01
# Reinstall node with new config
```

### Change Secrets

```bash
nano secrets.env
./build-ignition.sh all
# Reinstall affected nodes
```

---

## Troubleshooting

### Cilium Not Ready

Automatic fix is built-in (pod restart), but manual check:
```bash
kubectl get pods -n kube-system -l k8s-app=cilium
cilium status
```

### ArgoCD Not Installed

Check bootstrap logs:
```bash
ssh core@10.0.100.103
sudo journalctl -u argocd-install.service -f
```

### Node Won't Join

Check token and connectivity:
```bash
# Verify token
sudo cat /var/lib/rancher/rke2/server/node-token

# Check network
ping 10.0.100.103

# Check RKE2 logs
sudo journalctl -u rke2-server -f
```

### Butane Validation Error

```bash
# Test Butane syntax before building
butane --strict fcos-host03-bootstrap.bu

# Check for {{PLACEHOLDERS}} that weren't replaced
grep -n "{{" ignition/*.ign
```

---

## Security Notes

**Never committed to Git:**
- `secrets.env` - SSH keys, passwords, tokens
- `ignition/*.ign` - Compiled configs with embedded secrets

**Safe to commit:**
- `fcos-*.bu` - Templates with `{{PLACEHOLDERS}}`
- `build-ignition.sh` - Build script
- `secrets.env.example` - Template

**Additional protection:**
```bash
# Pre-commit hook (in repo root)
cat > .git/hooks/pre-commit << 'EOF'
#!/bin/bash
if git diff --cached --name-only | grep -E 'secrets.env|\.ign$|^coreos/ignition/'; then
  echo "❌ Error: Trying to commit secrets!"
  exit 1
fi
EOF
chmod +x .git/hooks/pre-commit
```

---

## Why Separate Files?

For 3 nodes with similar hardware, separate `.bu` files are clearer than complex templating:

**Pros:**
- ✅ Direct visibility into each node's config
- ✅ No scripting knowledge required to read
- ✅ Easy host-specific tweaks
- ✅ Simple debugging

**Cons:**
- ⚠️  Some duplication (but only 3 files)
- ⚠️  Cluster-wide changes need updates to all files

For 3 nodes, this is the right trade-off. Simplicity > abstraction.

---

## Reference

**Kubernetes:**
- Kubeconfig: `/etc/rancher/rke2/rke2.yaml` (also copied to `~/.kube/config`)
- RKE2 data: `/var/lib/rancher/rke2/`
- Manifests: `/var/lib/rancher/rke2/server/manifests/`

**Networking:**
- Bond interfaces: enp1s0 + enp1s0d1
- VLAN interface: vlan100
- Management: eno1

**Key Commands:**
```bash
# Cluster status
kubectl get nodes -o wide
kubectl get pods -A

# Cilium status
cilium status
kubectl exec -n kube-system ds/cilium -- cilium status

# Hubble
kubectl port-forward -n kube-system svc/hubble-ui 12000:80

# RKE2 logs
sudo journalctl -u rke2-server -f

# ArgoCD apps
kubectl get applications -n argocd
```

---

**Old documentation:** See [archive/](archive/) directory for previous template-based setup.
