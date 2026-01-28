# k8s-homelab-gitops

> GitOps-managed bare-metal Kubernetes homelab with Talos Linux, Cilium CNI, and automated ArgoCD deployment

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)
[![Kubernetes](https://img.shields.io/badge/Kubernetes-Talos-326CE5?logo=kubernetes)](https://talos.dev/)
[![ArgoCD](https://img.shields.io/badge/GitOps-ArgoCD-EF7B4D?logo=argo)](https://argoproj.github.io/cd/)
[![Cilium](https://img.shields.io/badge/CNI-Cilium-F8C517?logo=cilium)](https://cilium.io/)

---

## Architecture

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                              3-NODE HA CLUSTER                              │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                             │
│    host01 (Worker)     host02 (Worker)     host03 (Controlplane)            │
│    10.0.100.101        10.0.100.102        10.0.100.103                     │
│                                            VIP: 10.0.100.111                │
│                                                                             │
│  ┌─────────────────────────────────────────────────────────────────────┐    │
│  │  Talos Linux (Immutable, API-only)                                  │    │
│  │  ├─ Kubernetes (Talos-native, vanilla)                              │    │
│  │  ├─ Cilium CNI (eBPF, Gateway API, Hubble)                          │    │
│  │  ├─ Longhorn Storage (3x replica)                                   │    │
│  │  ├─ Multus (multi-NIC)                                              │    │
│  │  ├─ KubeVirt (VMs)                                                  │    │
│  │  └─ ArgoCD (GitOps, auto-deployed)                                  │    │
│  └─────────────────────────────────────────────────────────────────────┘    │
│                                                                             │
│  Network:  Management (eno1) → DHCP                                         │
│            Cluster (bond0 LACP 20G) → VLAN 100 (10.0.100.0/24)              │
│                                                                             │
│  Storage:  Pod Network 10.1.0.0/16  |  Service CIDR 10.2.0.0/16             │
│            OS: Smaller NVMe (<600GB) | Longhorn: Larger NVMe (2TB+)         │
│                                                                             │
└─────────────────────────────────────────────────────────────────────────────┘
```

---

## Quick Start

**Prerequisites:** 3x bare-metal servers, USB stick, 15-30 minutes

```bash
# 1. Clone repo
git clone https://github.com/Berndinox/k8s-homelab-gitops
cd k8s-homelab-gitops/talos

# 2. Setup secrets
cp secrets.env.example secrets.env
nano secrets.env  # Add SSH key, VIP, optional encryption

# 3. Generate Talos configs (includes Cilium + ArgoCD inline manifests)
./scripts/build-talos-configs.sh all

# 4. Create bootable USB (Windows: use Rufus, Linux/macOS: dd)
# Download: https://github.com/siderolabs/talos/releases/download/v1.9.3/metal-amd64.iso

# 5. Boot host03 from USB, apply config
talosctl apply-config --insecure --nodes 10.0.100.103 --file configs/host03.yaml

# 6. Bootstrap Kubernetes (Cilium + ArgoCD deploy automatically!)
talosctl bootstrap --nodes 10.0.100.103 --endpoints 10.0.100.103
talosctl kubeconfig --nodes 10.0.100.111

# 7. Wait for automatic deployment (~3-5 min)
kubectl get nodes -w  # Wait for Ready
kubectl get pods -A   # Cilium, ArgoCD, Infrastructure

# 8. Join worker nodes
talosctl apply-config --insecure --nodes 10.0.100.101 --file configs/host01.yaml
talosctl apply-config --insecure --nodes 10.0.100.102 --file configs/host02.yaml

# Done! Everything deployed automatically via GitOps! 🚀
```

**Full setup guide:** [talos/README.md](talos/README.md)

---

## Features

### 🏗️ Infrastructure as Code
- **Immutable OS**: Talos Linux - API-only, no SSH, fully declarative
- **Machine Configs**: All settings in YAML, versioned in Git
- **Automated**: USB boot → config apply → running cluster
- **Secure by Design**: Minimal attack surface, no package manager

### 🔄 GitOps Automation

- **ArgoCD**: Auto-deployed via inline manifests at bootstrap time
- **Zero Manual Steps**: Cilium, ArgoCD, and Root App deploy automatically
- **Sync Waves**: Guaranteed deployment order (Cilium → Longhorn → Multus → KubeVirt → Apps)
- **Self-Healing**: Git is source of truth, auto-sync enabled
- **App of Apps**: Single root app manages everything
- **Hybrid Bootstrap**: Combines Talos inline manifests with ArgoCD adoption

### 🌐 Advanced Networking
- **Cilium CNI**: eBPF-based, kube-proxy replacement
- **Gateway API**: Modern L7 policies (successor to Ingress)
- **LACP Bonding**: 20G aggregate bandwidth (2x 10G)
- **VLAN Isolation**: Separate management & cluster networks
- **BGP Ready**: Control plane enabled, peering ready
- **Hubble**: Observability & flow monitoring
- **VIP**: High-availability API endpoint (10.0.100.111)

### 💾 Storage & Compute
- **Longhorn**: Distributed block storage, 3x replication
- **Multus**: Multi-NIC support for VMs
- **KubeVirt**: Run VMs alongside containers

### 🔒 Security First
- **Talos**: No SSH by default, API-only management
- **Disk Encryption**: Optional LUKS2 encryption
- **Secrets**: Never committed to Git (.gitignored)
- **Pod Security**: Baseline enforcement, exemptions for system namespaces
- **Immutable**: OS changes require config re-apply

---

## Repository Structure

```
k8s-homelab-gitops/
├── talos/                       # 🔧 Talos Linux deployment
│   ├── configs/                 # Machine config templates
│   │   ├── base-patch.yaml.template         # Common settings
│   │   ├── controlplane-host03.yaml.template # Controlplane
│   │   ├── worker-host01.yaml.template      # Worker 1
│   │   └── worker-host02.yaml.template      # Worker 2
│   ├── scripts/                 # Helper scripts
│   │   ├── build-talos-configs.sh    # Config generator
│   │   ├── install-cilium.sh         # Cilium installer
│   │   ├── bootstrap-gitops.sh       # ArgoCD bootstrap
│   │   └── discover-disks.sh         # Disk discovery
│   ├── secrets/                 # Generated secrets (gitignored)
│   ├── README.md                # Full installation guide
│   ├── BOOTSTRAP-FLOW.md        # Visual deployment flow
│   ├── CHEATSHEET.md            # talosctl quick reference
│   ├── COMMON-ISSUES.md         # Troubleshooting guide
│   └── MIGRATION.md             # CoreOS→Talos migration (if needed)
│
├── bootstrap/                   # 🚀 GitOps root
│   └── root-app.yaml            # App of Apps (orchestrates everything)
│
├── argocd-apps/                 # 📦 Application definitions
│   ├── infrastructure.yaml      # Wave 0: Core infrastructure
│   └── apps.yaml                # Wave 10: Applications
│
├── infrastructure/              # 🏗️ Core components (deployed first)
│   ├── 00-cilium/               # CNI (deployed via Helm first, adopted by ArgoCD)
│   │   ├── cilium-helm.yaml    # ArgoCD app (adopts existing Helm install)
│   │   └── gateway-api-crds.yaml # Gateway API CRDs
│   ├── 01-longhorn/             # Storage (wave 1)
│   ├── 02-multus/               # Networking (wave 2)
│   └── 03-kubevirt/             # Virtualization (wave 3)
│
└── apps/                        # 🎯 Applications (deployed after infra)
    └── README.md                # How to add apps
```

---

## Deployment Flow

**Fully Automated:** Cilium, ArgoCD, and all infrastructure deploy automatically!

```
┌─────────────────────────────────────────────────────────────────────────────┐
│ PHASE 1: USB Boot & OS Installation (~5-10 min)                             │
├─────────────────────────────────────────────────────────────────────────────┤
│  • Boot from Talos USB (live environment)                                   │
│  • Apply machine config (talosctl apply-config)                             │
│  • Talos installs to disk (auto-selected by size)                           │
│  • Reboot to installed system                                               │
└────────────────────────────────┬────────────────────────────────────────────┘
                                 │
                                 ▼
┌─────────────────────────────────────────────────────────────────────────────┐
│ PHASE 2: Kubernetes Bootstrap - FULLY AUTOMATED! (~3-5 min)                 │
├─────────────────────────────────────────────────────────────────────────────┤
│  Command: talosctl bootstrap --nodes 10.0.100.103                           │
│                                                                             │
│  Automatically deployed via inline manifests:                               │
│  1. Network configuration (bond0 + VLAN 100)                                │
│  2. Kubernetes control plane (etcd, API server)                             │
│  3. VIP active (10.0.100.111 via KubePrism)                                 │
│  4. ✅ Cilium CNI (full featured: BGP, Gateway API, Hubble)                  │
│  5. ✅ ArgoCD GitOps operator                                                │
│  6. ✅ Root-of-roots App (points to argocd-apps/)                            │
│                                                                             │
│  Node becomes Ready! No manual steps needed!                                │
└────────────────────────────────┬────────────────────────────────────────────┘
                                 │
                                 ▼
┌─────────────────────────────────────────────────────────────────────────────┐
│ PHASE 3: Infrastructure Deployment (GitOps Sync Waves)                      │
├─────────────────────────────────────────────────────────────────────────────┤
│  ArgoCD automatically deploys infrastructure via sync waves:                │
│                                                                             │
│  Wave -5: Cilium (adopted from inline manifest)                             │
│  Wave  1: Longhorn (Storage)                              ~10-15 min        │
│  Wave  2: Multus (Multi-NIC)                                                │
│  Wave  3: KubeVirt (VMs)                                                    │
│                                                                             │
│  All fully automated via GitOps!                                            │
└────────────────────────────────┬────────────────────────────────────────────┘
                                 │
                                 ▼
┌─────────────────────────────────────────────────────────────────────────────┐
│ PHASE 4: Application Deployment (GitOps Sync Wave 10)                       │
├─────────────────────────────────────────────────────────────────────────────┤
│  • Automatic deployment of apps/                        ~Variable           │
│  • Only starts after infrastructure is healthy                              │
└────────────────────────────────┬────────────────────────────────────────────┘
                                 │
                                 ▼
┌─────────────────────────────────────────────────────────────────────────────┐
│ PHASE 5: Join Worker Nodes (host01, host02)                                 │
├─────────────────────────────────────────────────────────────────────────────┤
│  1. Boot from USB                                                           │
│  2. Apply worker config                                  ~5 min per node    │
│  3. Auto-join cluster via VIP                                               │
│  4. Cilium DaemonSet deployed automatically                                 │
└─────────────────────────────────────────────────────────────────────────────┘
```

**Total Time:** ~15-35 minutes from bare metal to fully operational 3-node cluster

**Key Benefit:** Zero manual steps after `talosctl bootstrap` - everything deploys automatically!

**Key Difference to other setups:** Cilium is installed **manually via Helm first**, then ArgoCD adopts it for ongoing management. This solves the chicken-egg problem (ArgoCD needs CNI to run as pods).

---

## Stack

| Layer | Component | Purpose |
|-------|-----------|---------|
| **OS** | Talos Linux | Immutable, minimal, Kubernetes-native |
| **Kubernetes** | Talos-native K8s | Vanilla Kubernetes, latest stable |
| **CNI** | Cilium | eBPF networking, Gateway API, kube-proxy replacement |
| **GitOps** | ArgoCD | Declarative continuous delivery |
| **Storage** | Longhorn | Distributed block storage |
| **Networking** | Multus | Multi-NIC support |
| **Compute** | KubeVirt | VM orchestration |
| **Observability** | Hubble | Network visibility |

---

## Management

### Talos API

```bash
# Export talosconfig
export TALOSCONFIG=$(pwd)/talos/secrets/talosconfig

# Node logs
talosctl logs kubelet --nodes 10.0.100.103

# Node shell (requires extension)
talosctl shell --nodes 10.0.100.103

# Node reboot
talosctl reboot --nodes 10.0.100.103

# Upgrade Talos
talosctl upgrade --nodes 10.0.100.103 --image ghcr.io/siderolabs/installer:v1.9.4 --preserve

# Upgrade Kubernetes
talosctl upgrade-k8s --nodes 10.0.100.103 --to 1.32.0
```

### Kubernetes

```bash
# ArgoCD UI
kubectl port-forward svc/argocd-server -n argocd 8080:443
# Visit: https://localhost:8080

# Get admin password
kubectl -n argocd get secret argocd-initial-admin-secret \
  -o jsonpath="{.data.password}" | base64 -d

# Watch deployments
kubectl get applications -n argocd -w

# Cluster status
kubectl get nodes -o wide
kubectl get pods -A

# Hubble UI
kubectl port-forward -n kube-system svc/hubble-ui 12000:80
# Visit: http://localhost:12000

# Cilium status
kubectl exec -n kube-system ds/cilium -- cilium status
```

---

## Why This Stack?

| Decision | Rationale |
|----------|-----------|
| **Talos Linux** | Immutable, API-only, secure by design, Kubernetes-native, minimal attack surface |
| **Vanilla K8s** | Latest features, no vendor lock-in, direct upstream updates |
| **Cilium** | eBPF performance, Gateway API, BGP, Hubble, kube-proxy replacement |
| **Gateway API** | Modern L7 routing, successor to Ingress, better policies |
| **ArgoCD** | GitOps standard, declarative, self-healing, easy rollbacks |
| **Helm → ArgoCD adoption** | Solves chicken-egg (CNI before ArgoCD), keeps GitOps |
| **Sync Waves** | Guaranteed deployment order, no manual dependencies |
| **Longhorn** | Cloud-native storage, 3x replication, snapshots, no external SAN |
| **VIP** | High availability API, no single point of failure |

---

## Roadmap

- [x] Talos 3-node HA cluster
- [x] LACP bonding + VLAN networking
- [x] VIP for API high availability
- [x] Cilium CNI with eBPF + Gateway API
- [x] Hubble observability
- [x] ArgoCD auto-deployment
- [x] GitOps sync waves
- [ ] Longhorn storage implementation
- [ ] Multus multi-NIC configuration
- [ ] KubeVirt VM support
- [ ] OPNsense VM via KubeVirt
- [ ] BGP peering with OPNsense
- [ ] Application deployments
- [ ] Monitoring stack (Prometheus/Grafana)
- [ ] Backup automation (etcd + Longhorn)

---

## Documentation

### Main Guides
- **[Talos Installation Guide](talos/README.md)** - Complete bare-metal setup
- **[Bootstrap Flow](talos/BOOTSTRAP-FLOW.md)** - Visual deployment process
- **[Common Issues](talos/COMMON-ISSUES.md)** - Troubleshooting guide
- **[Talosctl Cheatsheet](talos/CHEATSHEET.md)** - Quick command reference

### Additional
- **[Infrastructure README](infrastructure/README.md)** - Adding components
- **[Apps README](apps/README.md)** - Deploying applications

---

## Hardware Requirements

- **3x Servers** with:
  - 2x 10G NICs (for LACP bonding)
  - 2x NVMe disks:
    - Smaller (200-600GB) for Talos OS
    - Larger (2TB+) for Longhorn storage
  - Minimum 16GB RAM (32GB+ recommended for KubeVirt)
  - CPU with virtualization support (VT-x/AMD-V for KubeVirt)

- **Network**:
  - Switch with LACP (802.3ad) support
  - VLAN 100 configured and tagged on switch ports
  - Trunk mode on switch ports

---


## Troubleshooting

Quick diagnostics:

```bash
# Talos node not responding
talosctl --insecure --nodes <IP> get links

# Cilium not starting
kubectl logs -n kube-system ds/cilium -f
kubectl exec -n kube-system ds/cilium -- cilium status

# Node not Ready
kubectl describe node <node-name>
talosctl logs kubelet --nodes <IP>

# ArgoCD app OutOfSync
kubectl get application -n argocd <app-name> -o yaml
kubectl -n argocd patch app <app-name> -p '{"spec":{"syncPolicy":{"syncOptions":["Force=true"]}}}' --type merge
```

**Full troubleshooting guide:** [talos/COMMON-ISSUES.md](talos/COMMON-ISSUES.md)

---

## Disclaimer

This project is provided "as is" without any guarantee of functionality or security. It is a private hobby project. The author assumes no liability for damages arising from its use.

**Not for production use** - this is a homelab environment for learning and experimentation.

---

## License

MIT License - See [LICENSE](LICENSE) file for details.

---

## Resources

- [Talos Linux Documentation](https://www.talos.dev)
- [Cilium Documentation](https://docs.cilium.io)
- [ArgoCD Documentation](https://argo-cd.readthedocs.io)
- [Longhorn Documentation](https://longhorn.io/docs)
- [KubeVirt Documentation](https://kubevirt.io)
- [Gateway API Documentation](https://gateway-api.sigs.k8s.io)

---

**Built with ❤️ for homelabs**

*Powered by Talos Linux, Cilium eBPF, and GitOps best practices*
