# k8s-homelab-gitops

> GitOps-managed bare-metal Kubernetes homelab with RKE2, Cilium CNI, and automated ArgoCD deployment

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)
[![Kubernetes](https://img.shields.io/badge/Kubernetes-RKE2-326CE5?logo=kubernetes)](https://rke2.io/)
[![ArgoCD](https://img.shields.io/badge/GitOps-ArgoCD-EF7B4D?logo=argo)](https://argoproj.github.io/cd/)
[![Cilium](https://img.shields.io/badge/CNI-Cilium-F8C517?logo=cilium)](https://cilium.io/)

---

## Network Architecture

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                         BARE METAL INFRASTRUCTURE                           │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                             │
│   ┌──────────────────┐    ┌──────────────────┐    ┌──────────────────┐    │
│   │     host01       │    │     host02       │    │     host03       │    │
│   │  10.0.100.101    │    │  10.0.100.102    │    │  10.0.100.103    │    │
│   │                  │    │                  │    │  (Bootstrap)     │    │
│   │  Control Plane   │    │  Control Plane   │    │  Control Plane   │    │
│   │  + etcd          │    │  + etcd          │    │  + etcd          │    │
│   └────┬────────┬────┘    └────┬────────┬────┘    └────┬────────┬────┘    │
│        │        │              │        │              │        │         │
│     eno1     bond0          eno1     bond0          eno1     bond0        │
│      │    ┌───┴───┐          │    ┌───┴───┐          │    ┌───┴───┐      │
│      │  enp1s0 enp1s0d1      │  enp1s0 enp1s0d1      │  enp1s0 enp1s0d1  │
│      │    │       │           │    │       │           │    │       │      │
│      │    └───┬───┘           │    └───┬───┘           │    └───┬───┘      │
│      │      (LACP)            │      (LACP)            │      (LACP)       │
│      │      20Gbit            │      20Gbit            │      20Gbit       │
│      │        │               │        │               │        │          │
│  ┌───┴────────┴───────────────┴────────┴───────────────┴────────┴───────┐ │
│  │                        Management Switch (DHCP)                       │ │
│  │                         + Access Switch (VLAN 100)                    │ │
│  └───────────────────────────────────────────────────────────────────────┘ │
│                                                                             │
│  Management Network:  eno1 → DHCP                                          │
│  Cluster Network:     bond0 (VLAN 100) → 10.0.100.0/24                     │
│                                                                             │
├─────────────────────────────────────────────────────────────────────────────┤
│                           KUBERNETES CLUSTER                                │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                             │
│  CNI:           Cilium (eBPF, kube-proxy replacement)                      │
│  Pod Network:   10.1.0.0/16                                                │
│  Service CIDR:  10.2.0.0/16                                                │
│  Storage:       Longhorn (3x replica)                                      │
│  Networking:    Multus (multi-NIC)                                         │
│  Compute:       KubeVirt (VMs)                                             │
│  GitOps:        ArgoCD (auto-deployed)                                     │
│                                                                             │
└─────────────────────────────────────────────────────────────────────────────┘
```

---

## Quick Start

**Prerequisites:** 3x bare-metal servers, USB stick, 10 minutes

```bash
# 1. Clone repo
git clone https://github.com/Berndinox/k8s-homelab-gitops
cd k8s-homelab-gitops/coreos

# 2. Setup secrets
cp secrets.env.example secrets.env
nano secrets.env  # Add SSH key & password hash

# 3. Build bootstrap USB
./build-ignition.sh host03
sudo coreos-installer install /dev/sdX --ignition-file ignition/host03.ign

# 4. Boot server → Automatic deployment:
#    ✅ RKE2 Kubernetes
#    ✅ Cilium CNI
#    ✅ ArgoCD + GitOps
#    ✅ Infrastructure (Longhorn, Multus, KubeVirt)
#    ✅ Your apps

# 5. Get join token & deploy remaining nodes
ssh core@10.0.100.103 'sudo cat /var/lib/rancher/rke2/server/node-token'
# Add token to secrets.env
./build-ignition.sh all
# Install host01 & host02

# Done! 🚀
```

**Full setup guide:** [coreos/README.md](coreos/README.md)

---

## Features

### 🏗️ Infrastructure as Code
- **Immutable OS**: Fedora CoreOS with Ignition/Butane
- **Declarative**: All configs in Git
- **Automated**: Zero manual steps from USB boot to running cluster

### 🔄 GitOps Automation
- **ArgoCD**: Auto-deployed during bootstrap
- **Sync Waves**: Guaranteed deployment order (Longhorn → Multus → KubeVirt → Apps)
- **Self-Healing**: Git is source of truth, auto-sync enabled
- **App of Apps**: Single root app manages everything

### 🌐 Advanced Networking
- **Cilium CNI**: eBPF-based, kube-proxy replacement
- **LACP Bonding**: 20G aggregate bandwidth (2x 10G)
- **VLAN Isolation**: Separate management & cluster networks
- **BGP Ready**: Control plane enabled, peering ready
- **Hubble**: Observability & flow monitoring

### 💾 Storage & Compute
- **Longhorn**: Distributed block storage, 3x replication
- **Multus**: Multi-NIC support for VMs
- **KubeVirt**: Run VMs alongside containers

### 🔒 Security First
- **Secrets**: Never committed to Git (.gitignore + placeholders)
- **Immutable**: OS changes require redeployment
- **Encrypted**: Support for age/SOPS (optional)

---

## Repository Structure

```
k8s-homelab-gitops/
├── coreos/                      # 🔧 Bare-metal deployment
│   ├── fcos-host0X-*.bu        # Butane configs (separate per node)
│   ├── build-ignition.sh       # Smart build script
│   ├── secrets.env.example     # Template for secrets
│   └── README.md               # Full installation guide
│
├── bootstrap/                   # 🚀 GitOps root
│   └── root-app.yaml           # App of Apps (orchestrates everything)
│
├── argocd-apps/                 # 📦 Application definitions
│   ├── infrastructure.yaml     # Wave 0: Core infrastructure
│   └── apps.yaml               # Wave 10: Applications
│
├── infrastructure/              # 🏗️ Core components (deployed first)
│   ├── 00-namespaces/          # Kubernetes namespaces
│   ├── 01-longhorn/            # Storage (wave 1)
│   ├── 02-multus/              # Networking (wave 2)
│   └── 03-kubevirt/            # Virtualization (wave 3)
│
└── apps/                        # 🎯 Applications (deployed after infra)
    └── README.md               # How to add apps
```

---

## Deployment Flow

```
┌─────────────────────────────────────────────────────────────────────────────┐
│ PHASE 1: USB Boot & OS Installation (~5 min)                               │
└────────────────────────────────┬────────────────────────────────────────────┘
                                 │
                                 ▼
┌─────────────────────────────────────────────────────────────────────────────┐
│ PHASE 2: Kubernetes Bootstrap (host03)                                     │
├─────────────────────────────────────────────────────────────────────────────┤
│  1. Network Configuration (bond0 + VLAN 100)                               │
│  2. RKE2 Installation                                                      │
│  3. Cilium CNI Deployment                                ~10 min           │
│  4. ArgoCD Installation                                                    │
│  5. GitOps Bootstrap (root-app.yaml)                                       │
└────────────────────────────────┬────────────────────────────────────────────┘
                                 │
                                 ▼
┌─────────────────────────────────────────────────────────────────────────────┐
│ PHASE 3: Infrastructure Deployment (GitOps Sync Wave 0)                    │
├─────────────────────────────────────────────────────────────────────────────┤
│  Wave 0: Namespaces                                                        │
│  Wave 1: Longhorn (Storage)                                                │
│  Wave 2: Multus (Multi-NIC)                              ~10-15 min        │
│  Wave 3: KubeVirt (VMs)                                                    │
│                                                                             │
│  ⏳ Bootstrap script waits for infrastructure health                       │
└────────────────────────────────┬────────────────────────────────────────────┘
                                 │
                                 ▼
┌─────────────────────────────────────────────────────────────────────────────┐
│ PHASE 4: Application Deployment (GitOps Sync Wave 10)                      │
├─────────────────────────────────────────────────────────────────────────────┤
│  Automatic deployment of apps/                          ~Variable          │
│  Only starts after infrastructure is healthy                               │
└────────────────────────────────┬────────────────────────────────────────────┘
                                 │
                                 ▼
┌─────────────────────────────────────────────────────────────────────────────┐
│ PHASE 5: Join Additional Nodes (host01, host02)                            │
├─────────────────────────────────────────────────────────────────────────────┤
│  1. Add JOIN_TOKEN to secrets.env                                          │
│  2. Build join configs                                   ~5 min per node   │
│  3. Install from USB                                                       │
│  4. Auto-join cluster                                                      │
└─────────────────────────────────────────────────────────────────────────────┘
```

**Total Time:** ~30-40 minutes from bare metal to fully operational cluster

---

## Stack

| Layer | Component | Purpose |
|-------|-----------|---------|
| **OS** | Fedora CoreOS | Immutable, container-optimized |
| **Kubernetes** | RKE2 | Production-grade K8s distribution |
| **CNI** | Cilium | eBPF networking, kube-proxy replacement |
| **GitOps** | ArgoCD | Declarative continuous delivery |
| **Storage** | Longhorn | Distributed block storage |
| **Networking** | Multus | Multi-NIC support |
| **Compute** | KubeVirt | VM orchestration |
| **Observability** | Hubble | Network visibility |


---

## Monitoring

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
```

---

## Why This Stack?

| Decision | Rationale |
|----------|-----------|
| **Fedora CoreOS** | Immutable, auto-updating, optimized for containers, Ignition config |
| **RKE2** | Production-grade, secure by default, bundled components, easy upgrades |
| **Cilium** | eBPF performance, kube-proxy replacement, BGP, rich observability |
| **ArgoCD** | GitOps standard, declarative, self-healing, easy rollbacks |
| **Separate .bu files** | 3 nodes = clarity > abstraction, easy debugging, host-specific tweaks |
| **Sync Waves** | Guaranteed deployment order, no manual dependencies |
| **Longhorn** | Cloud-native storage, 3x replication, snapshots, no external SAN |

---

## Roadmap

- [x] RKE2 3-node HA cluster
- [x] Cilium CNI with BGP control plane
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
- [ ] Backup automation

---

## Documentation

- **[CoreOS Installation Guide](coreos/README.md)** - Complete bare-metal setup
- **[Infrastructure README](infrastructure/README.md)** - Adding components
- **[Apps README](apps/README.md)** - Deploying applications

---

## Disclaimer

This project is provided "as is" without any guarantee of functionality or security. It is a private hobby project. The author assumes no liability for damages arising from its use.

---

## License

MIT License - See [LICENSE](LICENSE) file for details.

---

**Built with ❤️ (and Claude) for homelabs**
