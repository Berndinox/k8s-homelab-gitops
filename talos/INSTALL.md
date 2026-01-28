# Talos Kubernetes Installation Guide

Complete step-by-step guide for deploying a Talos Kubernetes cluster with fully automated Cilium, ArgoCD, and GitOps infrastructure.

## Table of Contents

- [Overview](#overview)
- [Prerequisites](#prerequisites)
- [Installation Steps](#installation-steps)
- [Verification](#verification)
- [Joining Worker Nodes](#joining-worker-nodes)
- [Accessing Services](#accessing-services)
- [Troubleshooting](#troubleshooting)

---

## Overview

This installation uses **Hybrid Bootstrap** - a fully automated approach where:

1. **Talos** deploys Kubernetes
2. **Cilium CNI** is embedded in Talos config (inline manifests)
3. **ArgoCD** is embedded in Talos config (inline manifests)
4. **Root-of-roots App** is embedded in Talos config (inline manifests)
5. **All infrastructure** deploys automatically via GitOps

**Zero manual steps** after `talosctl bootstrap`!

### What Gets Deployed Automatically

```
talosctl bootstrap
  ↓
Kubernetes starts
  ↓
Inline Manifests Deploy:
  ✅ Cilium CNI (full featured)
  ✅ ArgoCD GitOps Operator
  ✅ Root App (points to argocd-apps/)
  ↓
ArgoCD Syncs Automatically:
  ✅ Infrastructure (Longhorn, Multus, KubeVirt)
  ✅ Applications (apps/)
```

---

## Prerequisites

### Hardware

- **3x Bare-metal servers** (or VMs with VT-x/AMD-V)
  - host01: Worker (10.0.100.101)
  - host02: Worker (10.0.100.102)
  - host03: Controlplane (10.0.100.103)
- **2x NVMe per host:**
  - Smaller (<600GB) for Talos OS
  - Larger (2TB+) for Longhorn storage
- **Network:**
  - 2x 10G NICs for LACP bonding
  - Switch with LACP (802.3ad) support
  - VLAN 100 configured and tagged on switch ports
- **USB Stick** (1GB+) for Talos installation

### Software

On your workstation (choose your OS):

#### Linux/macOS

```bash
# Install talosctl
curl -sL https://talos.dev/install | sh

# Install kubectl
curl -LO "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl"
chmod +x kubectl && sudo mv kubectl /usr/local/bin/

# Install helm (for manifest generation)
curl https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash
```

#### Windows

**Option 1: Using WSL2 (Recommended)**

```bash
# Install WSL2 first (PowerShell as Admin):
wsl --install

# Then in WSL2, follow Linux instructions above
```

**Option 2: Native Windows + Git Bash**

1. **Install talosctl:**
   - Download: https://github.com/siderolabs/talos/releases/latest
   - Extract `talosctl-windows-amd64.exe` to `C:\Program Files\talosctl\`
   - Rename to `talosctl.exe`
   - Add to PATH: `C:\Program Files\talosctl`

2. **Install kubectl:**
   - Download: https://kubernetes.io/docs/tasks/tools/install-kubectl-windows/
   - Or use Chocolatey: `choco install kubernetes-cli`

3. **Install Helm:**
   - Download: https://github.com/helm/helm/releases/latest
   - Or use Chocolatey: `choco install kubernetes-helm`

4. **Install Git Bash:**
   - Download: https://git-scm.com/download/win
   - Use Git Bash to run scripts (required for bash scripts!)

**Verify Installation (any OS):**

```bash
talosctl version --client
kubectl version --client
helm version
```

### Network Configuration

Ensure your switch is configured with:

- **LACP**: 802.3ad bonding enabled on ports connected to hosts
- **VLAN 100**: Tagged on all ports
- **Trunk Mode**: Ports configured for VLAN trunking

---

## Installation Steps

### Step 1: Clone Repository

```bash
git clone https://github.com/Berndinox/k8s-homelab-gitops
cd k8s-homelab-gitops/talos
```

### Step 2: Configure Secrets

```bash
# Copy example file
cp secrets.env.example secrets.env

# Edit secrets
nano secrets.env
```

**Required settings:**

```bash
# VIP for API server high availability
VIP_ADDRESS="10.0.100.111"

# SSH public key for Talos access (optional but recommended)
SSH_PUBLIC_KEY="ssh-ed25519 AAAAC3... user@host"

# DNS servers (comma-separated)
DNS_SERVERS="8.8.8.8,8.8.4.4"

# NTP servers (comma-separated)
NTP_SERVERS="pool.ntp.org"

# Disk encryption (optional)
DISK_ENCRYPTION_KEY=""  # Leave empty to disable

# GitOps repository (for ArgoCD)
GITOPS_REPO="https://github.com/Berndinox/k8s-homelab-gitops"
GITOPS_BRANCH="main"
```

### Step 3: Generate Talos Configurations

This script generates machine configs and **inline manifests** for Cilium, ArgoCD, and Root App.

```bash
./scripts/build-talos-configs.sh all
```

**What happens:**

1. Generates Talos secrets (`secrets/secrets.yaml`)
2. Generates inline manifests:
   - `manifests/cilium-inline.yaml` (from Helm template)
   - `manifests/argocd-inline.yaml` (from Helm template)
   - `manifests/root-app-inline.yaml` (copy of bootstrap/root-app.yaml)
3. Embeds inline manifests into controlplane config
4. Generates final machine configs:
   - `configs/host03.yaml` (controlplane with inline manifests)
   - `configs/host01.yaml` (worker)
   - `configs/host02.yaml` (worker)
5. Generates talosconfig (`secrets/talosconfig`)

**Output:**

```
✓ All configurations generated successfully!

Inline manifests embedded in controlplane config:
  • Cilium CNI (full featured)
  • ArgoCD GitOps operator
  • Root-of-roots application

Next steps:
  1. Review generated configs in: configs/
  2. Create bootable USB with Talos
  ...
```

### Step 4: Create Bootable USB

**On Windows (Rufus):**

1. Download Talos ISO:
   ```
   https://github.com/siderolabs/talos/releases/download/v1.9.3/metal-amd64.iso
   ```
2. Open Rufus
3. Select your USB stick
4. Select the Talos ISO
5. Partition scheme: **GPT**
6. Target system: **UEFI**
7. Click **START**

**On Linux/macOS:**

```bash
# Download ISO
wget https://github.com/siderolabs/talos/releases/download/v1.9.3/metal-amd64.iso

# Write to USB (replace /dev/sdX with your USB device!)
sudo dd if=metal-amd64.iso of=/dev/sdX bs=4M status=progress && sync
```

### Step 5: Boot and Configure host03 (Controlplane)

1. **Insert USB** into host03
2. **Boot from USB** (configure BIOS to boot UEFI, disable Secure Boot)
3. **Wait** for Talos to start (live environment)

**Apply configuration:**

```bash
# Set TALOSCONFIG environment variable
export TALOSCONFIG=$(pwd)/secrets/talosconfig

# Apply machine config to host03
talosctl apply-config \
  --insecure \
  --nodes 10.0.100.103 \
  --file configs/host03.yaml
```

**What happens:**

- Talos installs to disk (auto-selected by size: smaller NVMe <600GB)
- Node reboots automatically
- Wait 2-3 minutes for installation to complete

### Step 6: Bootstrap Kubernetes (AUTOMATIC DEPLOYMENT!)

```bash
# Bootstrap Kubernetes on host03
talosctl bootstrap \
  --nodes 10.0.100.103 \
  --endpoints 10.0.100.103 \
  --talosconfig secrets/talosconfig
```

**What happens automatically:**

1. **Kubernetes starts** (etcd, API server, controller-manager, scheduler)
2. **VIP activates** (10.0.100.111 via KubePrism)
3. **Cilium deploys** from inline manifest (full featured: BGP, Gateway API, Hubble)
4. **ArgoCD deploys** from inline manifest
5. **Root App deploys** from inline manifest (points to `argocd-apps/`)
6. **ArgoCD syncs** `infrastructure.yaml` and `apps.yaml`
7. **Infrastructure deploys** via sync waves:
   - Wave -5: Cilium (adopted from inline manifest)
   - Wave 1: Longhorn (storage)
   - Wave 2: Multus (multi-NIC)
   - Wave 3: KubeVirt (VMs)
8. **Apps deploy** via sync wave 10

**Total time:** ~3-5 minutes for bootstrap, ~10-15 minutes for full infrastructure

### Step 7: Get Kubeconfig

```bash
# Fetch kubeconfig from VIP
talosctl kubeconfig \
  --nodes 10.0.100.111 \
  --endpoints 10.0.100.111 \
  --talosconfig secrets/talosconfig

# Verify connection
kubectl get nodes
```

**Expected output:**

```
NAME     STATUS   ROLES           AGE   VERSION
host03   Ready    control-plane   5m    v1.32.1
```

---

## Verification

### Check Node Status

```bash
kubectl get nodes -o wide
```

Should show `Ready` status.

### Check Cilium

```bash
# Check Cilium pods
kubectl get pods -n kube-system -l k8s-app=cilium

# Check Cilium status
kubectl exec -n kube-system ds/cilium -- cilium status --brief
```

### Check ArgoCD

```bash
# Check ArgoCD pods
kubectl get pods -n argocd

# Check Applications
kubectl get applications -n argocd
```

**Expected applications:**

- `root-apps` (App-of-Apps)
- `infrastructure` (Infrastructure components)
- `apps` (User applications)

### Check Infrastructure

```bash
# Watch infrastructure deployment
kubectl get application infrastructure -n argocd -w

# Check specific components
kubectl get pods -n longhorn-system  # Longhorn storage
kubectl get pods -n kube-system -l app=multus  # Multus
kubectl get pods -n kubevirt  # KubeVirt
```

### Check Sync Status

```bash
# Check all ArgoCD apps
kubectl get applications -n argocd -o wide

# Detailed status
argocd app list  # Requires argocd CLI
```

---

## Joining Worker Nodes

### Boot and Configure host01

```bash
# 1. Insert USB and boot host01
# 2. Apply configuration
talosctl apply-config \
  --insecure \
  --nodes 10.0.100.101 \
  --file configs/host01.yaml

# 3. Wait for node to join (~5 min)
kubectl get nodes -w
```

### Boot and Configure host02

```bash
# 1. Insert USB and boot host02
# 2. Apply configuration
talosctl apply-config \
  --insecure \
  --nodes 10.0.100.102 \
  --file configs/host02.yaml

# 3. Wait for node to join (~5 min)
kubectl get nodes -w
```

### Verify Cluster

```bash
kubectl get nodes -o wide
```

**Expected output:**

```
NAME     STATUS   ROLES           AGE   VERSION
host01   Ready    <none>          5m    v1.32.1
host02   Ready    <none>          5m    v1.32.1
host03   Ready    control-plane   20m   v1.32.1
```

---

## Accessing Services

### ArgoCD UI

```bash
# Get initial admin password
kubectl -n argocd get secret argocd-initial-admin-secret \
  -o jsonpath="{.data.password}" | base64 -d

# Access via LoadBalancer IP
kubectl get svc -n argocd argocd-server
```

**Login:**

- URL: `http://<argocd-server-external-ip>`
- Username: `admin`
- Password: (from command above)

### Hubble UI (Cilium Observability)

```bash
# Port-forward Hubble UI
kubectl port-forward -n kube-system svc/hubble-ui 12000:80

# Open browser
open http://localhost:12000
```

### Longhorn UI

```bash
# Port-forward Longhorn UI
kubectl port-forward -n longhorn-system svc/longhorn-frontend 8080:80

# Open browser
open http://localhost:8080
```

---

## Troubleshooting

### Node Not Ready

```bash
# Check Cilium status
kubectl get pods -n kube-system -l k8s-app=cilium

# Check Cilium logs
kubectl logs -n kube-system ds/cilium --tail=100

# Verify network configuration
talosctl get links --nodes 10.0.100.103
```

### ArgoCD Not Deploying

```bash
# Check ArgoCD pods
kubectl get pods -n argocd

# Check ArgoCD logs
kubectl logs -n argocd deployment/argocd-server

# Check application status
kubectl describe application infrastructure -n argocd
```

### Infrastructure Components Failing

```bash
# Check application sync status
kubectl get applications -n argocd

# Check specific component
kubectl describe application longhorn -n argocd

# Force sync
kubectl -n argocd patch app longhorn \
  -p '{"spec":{"syncPolicy":{"syncOptions":["Force=true"]}}}' --type merge
```

### Disk Not Detected

```bash
# Check available disks
talosctl disks --nodes 10.0.100.103

# Check disk selector in config
grep -A 5 "install:" configs/host03.yaml
```

### More Issues

See comprehensive troubleshooting guide: [COMMON-ISSUES.md](COMMON-ISSUES.md)

---

## Next Steps

- **Add Applications**: See [../apps/README.md](../apps/README.md)
- **Configure Multus VLANs**: See [../infrastructure/02-multus/README.md](../infrastructure/02-multus/README.md)
- **Deploy VMs with KubeVirt**: See [../infrastructure/03-kubevirt/README.md](../infrastructure/03-kubevirt/README.md)
- **Talos Commands**: See [CHEATSHEET.md](CHEATSHEET.md)

---

## Summary

✅ Fully automated deployment - zero manual steps after bootstrap!

✅ Cilium, ArgoCD, and infrastructure deploy automatically

✅ GitOps-ready from day one

✅ Production-ready patterns (HA, replication, encryption)

✅ Complete disaster recovery: Re-run bootstrap to restore cluster

**Total deployment time:** ~15-30 minutes from bare metal to running cluster!
