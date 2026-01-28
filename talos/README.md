# Talos Linux Kubernetes Homelab

This directory contains Talos Linux configurations for a 3-node Kubernetes homelab cluster with **fully automated** GitOps deployment.

## 🚀 Quick Start

**Want to get started?** See **[INSTALL.md](INSTALL.md)** for the complete step-by-step installation guide.

**Key Feature:** Everything deploys automatically! Cilium, ArgoCD, and all infrastructure are embedded as inline manifests in the Talos config and deploy automatically when you run `talosctl bootstrap`.

---

## What is Talos Linux?

**Talos Linux** is an immutable, minimal Linux distribution designed specifically for Kubernetes:

- **Secure by Design**: No SSH by default, API-only management
- **Immutable**: No shell access, no package manager, fully declarative
- **Minimal Attack Surface**: Only runs Kubernetes, nothing else
- **Fast**: Quick boot times and updates
- **Kubernetes-Native**: Built specifically for running Kubernetes

---

## Architecture Overview

### Cluster Configuration

- **3-Node HA Control Plane**: All nodes are both control plane and worker
  - **All nodes** have inline manifests (Cilium, ArgoCD, Root App) embedded
  - **Any node** can be used as the bootstrap node (recommended: host03)
  - **Other nodes** join the existing etcd cluster automatically
- **VIP**: 10.0.100.111 (High-availability API endpoint via KubePrism)
- **Kubernetes**: Talos-native (latest stable, currently v1.35.0 via Talos v1.12.1)

### Infrastructure Stack

- **CNI**: Cilium with eBPF (kube-proxy replacement, BGP, Gateway API, Hubble)
- **Storage**: Longhorn (distributed block storage, 3x replication)
- **Networking**: Multus (multi-NIC support for VMs)
- **Virtualization**: KubeVirt (KVM-based VMs)
- **GitOps**: ArgoCD (auto-deployed, manages all infrastructure)

### Network Layout

#### Management Network (eno1)

- DHCP-assigned IPs for host management

#### Cluster Network (bond0.100)

- **Bond0**: LACP 802.3ad bonding (enp1s0 + enp1s0d1) = 20G aggregate
- **VLAN 100**: Cluster traffic isolation
- **IPs**: 10.0.100.101-103/24 + VIP 10.0.100.111/24

#### Kubernetes Networks

- **Pod CIDR**: 10.1.0.0/16 (Cilium)
- **Service CIDR**: 10.2.0.0/16
- **DNS**: CoreDNS at 10.2.0.10

### Storage Layout

Each node has 2x NVMe disks:

- **Smaller NVMe (<600GB)**: Talos OS (auto-selected by size)
- **Larger NVMe (2TB+)**: Longhorn storage

---

## Directory Structure

```text
talos/
├── README.md                           # This file (overview)
├── INSTALL.md                          # Complete installation guide
├── secrets.env.example                 # Template for secrets
├── configs/                            # Talos machine config templates
│   ├── base-patch.yaml.template            # Common settings
│   ├── controlplane-host03.yaml.template   # Control plane node 3
│   ├── controlplane-host01.yaml.template   # Control plane node 1
│   └── controlplane-host02.yaml.template   # Control plane node 2
│   # Note: All nodes have inline manifests - any can bootstrap
├── manifests/                          # Generated inline manifests (gitignored)
│   ├── cilium-inline.yaml              # Auto-generated from Helm
│   ├── argocd-inline.yaml              # Auto-generated from Helm
│   └── root-app-inline.yaml            # Copy of bootstrap/root-app.yaml
├── scripts/                            # Helper scripts
│   ├── build-talos-configs.sh          # Generates configs + inline manifests
│   ├── generate-inline-manifests.sh    # Generates Cilium/ArgoCD/Root App YAML
│   └── discover-disks.sh               # Disk discovery helper
└── secrets/                            # Generated secrets (gitignored)
    ├── secrets.yaml                    # Talos cluster secrets
    └── talosconfig                     # Talos API client config
```

---

## Deployment Flow

**Fully Automated - Zero Manual Steps After Bootstrap!**

```text
1. Generate Configs
   └─> ./scripts/build-talos-configs.sh all
       ├─> Generates Talos secrets
       ├─> Generates inline manifests (Cilium, ArgoCD, Root App)
       ├─> Embeds manifests into ALL controlplane configs
       └─> Creates machine configs for all nodes

2. Boot & Install (any node, recommended: host03)
   └─> Boot from USB → Apply config → Talos installs to disk

3. Bootstrap Kubernetes
   └─> talosctl bootstrap --nodes 10.0.100.103
       ├─> Kubernetes starts (etcd, API server, scheduler, controller-manager)
       ├─> VIP activates (10.0.100.111)
       ├─> Cilium deploys (inline manifest) → CNI ready
       ├─> ArgoCD deploys (inline manifest) → GitOps ready
       ├─> Root App deploys (inline manifest) → Points to argocd-apps/
       └─> ArgoCD syncs infrastructure automatically

4. Infrastructure Auto-Deploys (GitOps Sync Waves)
   ├─> Wave -5: Cilium (adopted from inline manifest)
   ├─> Wave  1: Longhorn (storage)
   ├─> Wave  2: Multus (multi-NIC)
   ├─> Wave  3: KubeVirt (VMs)
   └─> Wave 10: Apps

5. Join Additional Nodes (host01, host02)
   └─> Boot from USB → Apply config → Auto-join etcd cluster
```

**Total Time:** ~15-30 minutes from bare metal to fully operational cluster

---

## Key Features

### Hybrid Bootstrap Pattern

- **Inline Manifests**: Cilium, ArgoCD, and Root App are embedded directly in Talos config
- **Auto-Deploy**: Everything deploys automatically at bootstrap time
- **GitOps Adoption**: ArgoCD adopts Cilium and manages it going forward
- **Zero Manual Steps**: No chicken-egg problem, no manual installations

### Security

- **API-Only Management**: No SSH by default (use talosctl)
- **Immutable OS**: No package manager, no shell access
- **Disk Encryption**: Optional LUKS2 encryption
- **Pod Security**: Baseline enforcement with exemptions for system namespaces
- **RBAC**: Enabled by default

### High Availability

- **3-Node etcd Cluster**: All nodes are control plane
- **VIP**: 10.0.100.111 for API server (no single point of failure)
- **LACP Bonding**: 20G aggregate bandwidth with failover
- **Distributed Storage**: Longhorn 3x replication

---

## Quick Commands

### Generate Configurations

```bash
cd talos
./scripts/build-talos-configs.sh all
```

### Bootstrap Cluster (host03)

```bash
# Apply config
talosctl apply-config --insecure --nodes 10.0.100.103 --file configs/host03.yaml

# Bootstrap Kubernetes
export TALOSCONFIG=$(pwd)/secrets/talosconfig
talosctl bootstrap --nodes 10.0.100.103 --endpoints 10.0.100.103

# Get kubeconfig
talosctl kubeconfig --nodes 10.0.100.111 --endpoints 10.0.100.111
```

### Join Additional Nodes

```bash
talosctl apply-config --insecure --nodes 10.0.100.101 --file configs/host01.yaml
talosctl apply-config --insecure --nodes 10.0.100.102 --file configs/host02.yaml
```

### Verify Deployment

```bash
kubectl get nodes -o wide
kubectl get pods -A
kubectl get applications -n argocd
```

---

## Management

### Talos Commands

```bash
# Node logs
talosctl logs kubelet --nodes 10.0.100.103

# Service status
talosctl services --nodes 10.0.100.103

# Network interfaces
talosctl get links --nodes 10.0.100.103

# Node reboot
talosctl reboot --nodes 10.0.100.103

# Upgrade Talos
talosctl upgrade --nodes 10.0.100.103 --image ghcr.io/siderolabs/installer:v1.9.4
```

### Kubernetes Access

```bash
# ArgoCD UI
kubectl port-forward svc/argocd-server -n argocd 8080:443

# Get ArgoCD admin password
kubectl -n argocd get secret argocd-initial-admin-secret \
  -o jsonpath="{.data.password}" | base64 -d

# Hubble UI (Cilium observability)
kubectl port-forward -n kube-system svc/hubble-ui 12000:80

# Cilium status
kubectl exec -n kube-system ds/cilium -- cilium status
```

---

## Troubleshooting

### Quick Diagnostics

```bash
# Node not Ready
talosctl logs kubelet --nodes <node-ip>
kubectl describe node <node-name>

# Cilium issues
kubectl logs -n kube-system ds/cilium -f
kubectl exec -n kube-system ds/cilium -- cilium status

# ArgoCD issues
kubectl get applications -n argocd
kubectl describe application <app-name> -n argocd

# Network issues
talosctl get links --nodes <node-ip>
talosctl get routes --nodes <node-ip>
```

For comprehensive troubleshooting, see [COMMON-ISSUES.md](COMMON-ISSUES.md)

---

## Documentation

- **[INSTALL.md](INSTALL.md)** - Complete step-by-step installation guide
- **[BOOTSTRAP-FLOW.md](BOOTSTRAP-FLOW.md)** - Visual deployment flow diagram
- **[COMMON-ISSUES.md](COMMON-ISSUES.md)** - Troubleshooting guide
- **[CHEATSHEET.md](CHEATSHEET.md)** - talosctl quick reference

---

## Resources

- [Talos Linux Documentation](https://www.talos.dev)
- [Cilium Documentation](https://docs.cilium.io)
- [ArgoCD Documentation](https://argo-cd.readthedocs.io)
- [Longhorn Documentation](https://longhorn.io/docs)
- [KubeVirt Documentation](https://kubevirt.io)
- [Gateway API Documentation](https://gateway-api.sigs.k8s.io)

---

## Support

This is a homelab project provided as-is for learning and experimentation.

**Not for production use.**

For issues:

- Check Talos logs: `talosctl logs --nodes <node-ip>`
- Check Kubernetes events: `kubectl get events -A`
- Check ArgoCD UI for application status
- See [COMMON-ISSUES.md](COMMON-ISSUES.md)

---

Built with ❤️ for homelabs - Powered by Talos Linux, Cilium eBPF, and GitOps best practices
