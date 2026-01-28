# Talos Linux Kubernetes Homelab

This directory contains Talos Linux configurations for a 3-node Kubernetes homelab cluster with GitOps automation via ArgoCD.

## Overview

**Talos Linux** is an immutable, minimal Linux distribution designed specifically for Kubernetes. It provides:
- Secure, hardened OS (no SSH by default, API-only management)
- Immutable infrastructure (no shell access by default)
- Declarative configuration
- Built-in security best practices
- Fast boot times and updates

## Architecture

### Infrastructure Components

- **3 Nodes:** host01 (worker), host02 (worker), host03 (controlplane)
- **Kubernetes Distribution:** Talos-native (latest stable)
- **CNI:** Cilium with eBPF (kube-proxy replacement)
- **Storage:** Longhorn (distributed storage)
- **Networking:** Multus (multi-NIC support)
- **Virtualization:** KubeVirt (KVM-based VMs)
- **GitOps:** ArgoCD

### Network Configuration

#### Management Network (eno1)
- DHCP-assigned IPs for host management

#### Cluster Network (bond0.100)
- **Bond0:** LACP 802.3ad bonding (enp1s0 + enp1s0d1)
- **VLAN 100:** Cluster traffic isolation
- **IPs:**
  - host01: 10.0.100.101/24
  - host02: 10.0.100.102/24
  - host03: 10.0.100.103/24
  - VIP (API): 10.0.100.111/24

#### Kubernetes Networks
- **Pod Network:** 10.1.0.0/16 (Cilium)
- **Service Network:** 10.2.0.0/16
- **DNS:** CoreDNS at 10.2.0.10

### Storage Configuration

Each node has 2x NVMe disks:
- **Smaller NVMe (200-600GB):** Talos OS
- **Larger NVMe (2TB):** Longhorn storage

## Directory Structure

```
talos/
├── README.md                           # This file
├── secrets.env.example                 # Template for secrets
├── .gitignore                          # Git ignore rules
├── configs/                            # Talos configurations
│   ├── base-patch.yaml.template        # Common settings for all nodes
│   ├── controlplane-host03.yaml.template  # Controlplane-specific config
│   ├── worker-host01.yaml.template     # Worker host01 config
│   └── worker-host02.yaml.template     # Worker host02 config
├── scripts/                            # Helper scripts
│   ├── build-talos-configs.sh          # Generate Talos configs
│   ├── bootstrap-gitops.sh             # Bootstrap ArgoCD and GitOps
│   └── discover-disks.sh               # Disk discovery helper
└── secrets/                            # Generated secrets (gitignored)
    ├── secrets.yaml                    # Talos cluster secrets
    └── talosconfig                     # Talos API client config
```

## Prerequisites

### Required Software

1. **talosctl** (Talos CLI)
   ```bash
   # Linux
   curl -sL https://talos.dev/install | sh

   # macOS
   brew install siderolabs/tap/talosctl
   ```

2. **kubectl** (Kubernetes CLI)
   ```bash
   # Linux
   curl -LO "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl"
   chmod +x kubectl && sudo mv kubectl /usr/local/bin/

   # macOS
   brew install kubectl
   ```

3. **USB Flash Drive** (8GB+) for Talos installation

### Hardware Requirements

- **3 x Servers** with:
  - 2x 10G NICs (for LACP bonding)
  - 2x NVMe disks (OS + storage)
  - Minimum 16GB RAM (32GB+ recommended for KubeVirt)
  - CPU with virtualization support (VT-x/AMD-V)

## Quick Start

### 1. Configure Secrets

```bash
cd talos
cp secrets.env.example secrets.env
```

Edit `secrets.env` and configure:
```bash
# Generate SSH key
ssh-keygen -t ed25519 -C "talos-homelab"
cat ~/.ssh/id_ed25519.pub  # Copy to SSH_PUBLIC_KEY

# Configure VIP (already set to 10.0.100.111)
VIP_ADDRESS='10.0.100.111'

# Optional: Disk encryption
DISK_ENCRYPTION_KEY=$(openssl rand -base64 32)

# Optional: GitOps repo
GITOPS_REPO='https://github.com/YOUR_USERNAME/k8s-homelab-gitops.git'
GITOPS_BRANCH='main'
```

### 2. Generate Talos Configurations

```bash
cd talos
./scripts/build-talos-configs.sh all
```

This generates:
- `configs/host01.yaml` - Worker node 1
- `configs/host02.yaml` - Worker node 2
- `configs/host03.yaml` - Controlplane node
- `secrets/secrets.yaml` - Cluster secrets
- `secrets/talosconfig` - Talos API client config

### 3. Create Bootable USB

Download Talos ISO:
```bash
talosctl image default --arch amd64
```

Write to USB drive:
```bash
# Linux (replace /dev/sdX with your USB device)
sudo dd if=talos-amd64.iso of=/dev/sdX bs=4M status=progress && sync

# macOS (replace /dev/diskX with your USB device)
sudo dd if=talos-amd64.iso of=/dev/diskX bs=4m && sync
```

### 4. Install Talos on host03 (Controlplane)

1. **Boot host03 from USB**
2. **Discover disk layout** (optional):
   ```bash
   ./scripts/discover-disks.sh 10.0.100.103
   ```
3. **Apply configuration:**
   ```bash
   talosctl apply-config --insecure \
     --nodes 10.0.100.103 \
     --file configs/host03.yaml
   ```
4. **Wait for installation** (2-5 minutes)

### 5. Bootstrap Kubernetes

```bash
# Export talosconfig
export TALOSCONFIG=$(pwd)/secrets/talosconfig

# Bootstrap Kubernetes on host03
talosctl bootstrap \
  --nodes 10.0.100.103 \
  --endpoints 10.0.100.103

# Wait for API to be ready (5-10 minutes)
talosctl health --server --nodes 10.0.100.103

# Get kubeconfig
talosctl kubeconfig \
  --nodes 10.0.100.111 \
  --endpoints 10.0.100.111
```

### 6. Install Cilium CNI

**IMPORTANT:** Cilium must be installed BEFORE ArgoCD (chicken-egg problem: ArgoCD runs as pods, pods need CNI)

```bash
./scripts/install-cilium.sh
```

This will:
- Install Cilium via Helm
- Wait for Cilium to be ready
- Prepare for ArgoCD adoption

Verify Cilium is running:
```bash
kubectl get pods -n kube-system -l k8s-app=cilium
kubectl exec -n kube-system ds/cilium -- cilium status
```

### 7. Bootstrap GitOps (ArgoCD)

```bash
./scripts/bootstrap-gitops.sh
```

This will:
1. Check Cilium is ready
2. Install ArgoCD
3. Create root GitOps application
4. Bootstrap infrastructure (Longhorn, Multus, KubeVirt)

After ArgoCD is running, it will adopt the existing Cilium installation and manage it via GitOps going forward.

### 8. Join Worker Nodes

Repeat for host01 and host02:

1. **Boot from USB**
2. **Apply configuration:**
   ```bash
   talosctl apply-config --insecure \
     --nodes 10.0.100.101 \
     --file configs/host01.yaml

   talosctl apply-config --insecure \
     --nodes 10.0.100.102 \
     --file configs/host02.yaml
   ```
3. **Verify nodes joined:**
   ```bash
   kubectl get nodes -o wide
   ```

## Post-Installation

### Access ArgoCD UI

```bash
# Get admin password
kubectl -n argocd get secret argocd-initial-admin-secret \
  -o jsonpath="{.data.password}" | base64 -d

# Port-forward
kubectl port-forward svc/argocd-server -n argocd 8080:443

# Open browser
open https://localhost:8080
```

### Access Hubble UI (Cilium)

```bash
kubectl port-forward -n kube-system svc/hubble-ui 12000:80
open http://localhost:12000
```

### Verify Infrastructure

```bash
# Check all pods
kubectl get pods -A

# Check Cilium status
kubectl exec -n kube-system ds/cilium -- cilium status

# Check Longhorn (after deployed)
kubectl get pods -n longhorn-system

# Check KubeVirt (after deployed)
kubectl get pods -n kubevirt
```

## Configuration Details

### Cilium Features

- **eBPF kube-proxy replacement** (no iptables)
- **Hubble** network observability
- **BGP Control Plane** for advanced routing
- **Gateway API** for L7 policies
- **Native routing** (no overlay)
- **Bandwidth management** with BBR
- **Host firewall** enabled

### Security Features

- **Disk encryption** (LUKS2, optional)
- **API-only management** (no SSH)
- **Immutable OS** (no package manager)
- **Pod Security Standards** (baseline enforced)
- **RBAC** enabled

### Network Features

- **LACP bonding** (802.3ad) for 20G aggregate bandwidth
- **VLAN isolation** for cluster traffic
- **VIP** for API server high availability
- **Multus** for multiple network interfaces
- **Cilium** for pod networking and policies

## Troubleshooting

### View Talos Logs

```bash
# System logs
talosctl logs --nodes 10.0.100.103

# Kubelet logs
talosctl logs kubelet --nodes 10.0.100.103

# Service logs
talosctl logs etcd --nodes 10.0.100.103
```

### Check Talos Services

```bash
talosctl services --nodes 10.0.100.103
```

### Reset a Node

```bash
# Graceful reset (preserves data)
talosctl reset --graceful --nodes 10.0.100.103

# Factory reset (wipes everything)
talosctl reset --wipe --nodes 10.0.100.103
```

### Check Network Configuration

```bash
# View network interfaces
talosctl get links --nodes 10.0.100.103

# View routes
talosctl get routes --nodes 10.0.100.103

# View addresses
talosctl get addresses --nodes 10.0.100.103
```

### Debug Cilium

```bash
# Cilium status
kubectl exec -n kube-system ds/cilium -- cilium status

# Connectivity test
kubectl exec -n kube-system ds/cilium -- cilium connectivity test

# View BGP status
kubectl exec -n kube-system ds/cilium -- cilium bgp routes
```

### Common Issues

#### 1. Node Not Joining Cluster

**Symptoms:** Node shows in `talosctl get members` but not in `kubectl get nodes`

**Solution:**
- Check Cilium is running on controlplane
- Verify network connectivity (ping VIP)
- Check kubelet logs: `talosctl logs kubelet --nodes <node-ip>`

#### 2. Cilium Pods Not Starting

**Symptoms:** Cilium pods stuck in `Init` or `CrashLoopBackOff`

**Solution:**
- Verify kube-proxy is disabled in Talos config
- Check kernel modules: `talosctl read /proc/modules --nodes <node-ip>`
- Restart Cilium: `kubectl rollout restart ds/cilium -n kube-system`

#### 3. VIP Not Accessible

**Symptoms:** Cannot reach API server via VIP (10.0.100.111)

**Solution:**
- Check VIP configuration in controlplane config
- Verify VLAN interface is up: `talosctl get links --nodes 10.0.100.103`
- Check routing: `talosctl get routes --nodes 10.0.100.103`

#### 4. Disk Not Detected

**Symptoms:** Talos fails to install, disk not found

**Solution:**
- Boot from USB and check disks: `./scripts/discover-disks.sh <node-ip>`
- Update `diskSelector` in base-patch.yaml.template
- Rebuild configs: `./scripts/build-talos-configs.sh all`

## Maintenance

### Update Talos

```bash
# Check current version
talosctl version --nodes 10.0.100.103

# Update (example to v1.9.4)
talosctl upgrade --nodes 10.0.100.103 \
  --image ghcr.io/siderolabs/installer:v1.9.4

# Monitor upgrade
talosctl health --server --nodes 10.0.100.103
```

### Update Kubernetes

```bash
# Check current version
kubectl version --short

# Update via Talos (example to 1.32.0)
talosctl upgrade-k8s --nodes 10.0.100.103 --to 1.32.0
```

### Backup etcd

```bash
talosctl etcd snapshot --nodes 10.0.100.103
```

### Restore etcd

```bash
talosctl bootstrap recover --source /path/to/snapshot --nodes 10.0.100.103
```

## Migration from CoreOS

If migrating from CoreOS (RKE2):

1. **Backup persistent data** from Longhorn
2. **Export application configs** from ArgoCD
3. **Follow Quick Start** to deploy Talos cluster
4. **Restore data** to new Longhorn volumes
5. **Sync applications** via ArgoCD

Key differences:
- No Ignition/Butane (use Talos machine configs)
- No RKE2 (use Talos-native Kubernetes)
- No SSH by default (use talosctl)
- Immutable OS (no package installation)

## Resources

- [Talos Linux Documentation](https://www.talos.dev)
- [Cilium Documentation](https://docs.cilium.io)
- [ArgoCD Documentation](https://argo-cd.readthedocs.io)
- [Longhorn Documentation](https://longhorn.io/docs)
- [KubeVirt Documentation](https://kubevirt.io/user-guide)
- [Multus Documentation](https://github.com/k8snetworkplumbingwg/multus-cni)

## Support

For issues specific to this homelab setup, check:
- Talos logs: `talosctl logs --nodes <node-ip>`
- Kubernetes events: `kubectl get events -A`
- ArgoCD UI for application status

## License

This configuration is provided as-is for homelab use.
