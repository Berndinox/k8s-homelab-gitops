# k8s-homelab-gitops

GitOps-managed Kubernetes homelab cluster with RKE2, Cilium CNI, and ArgoCD.

**Disclaimer**: This project is provided "as is". It is a private hobby project without any guarantee of functionality or security. The author assumes no liability for damages arising from use.

## 🎯 Cluster Overview

**Infrastructure:**
- 3x Control-Plane Nodes (Fedora CoreOS)
- RKE2 Kubernetes Distribution
- High Availability etcd
- Cilium CNI with BGP Control Plane
- KubeVirt and Multus for enhanced networking
- GitOps via ArgoCD

**Network Architecture:**
```
3x Fedora CoreOS Hosts (host01, host02, host03)
├── Management: DHCP via eno1
├── Cluster: VLAN 100 (10.0.100.0/24) - bond0 (LACP 20Gbit)
├── Pod Network: 10.1.0.0/16 (Cilium VXLAN)
└── Service Network: 10.2.0.0/16
```

---

## 📁 Repository Structure

Logical order from bare-metal installation to GitOps:

```
k8s-homelab-gitops/
├── coreos/              # Fedora CoreOS installation configs
├── argocd-apps/         # ArgoCD application definitions
├── bootstrap/           # GitOps bootstrap manifests
├── infrastructure/      # Core infrastructure components
└── apps/                # Application deployments
```

---

## 📦 Stack Components

### Layer 1: Infrastructure (CoreOS Immutable Install)

| Component | Status |
|-----------|--------|
| RKE2 | ✅ Done |
| Cilium CNI | ✅ Done |
| ArgoCD | ✅ Done |

### Layer 2: GitOps Managed (via ArgoCD)

| Component | Status |
|-----------|--------|
| Namespaces | ✅ Done |
| Longhorn | ⏳ Planned |
| Multus | ⏳ Planned |
| KubeVirt | ⏳ Planned |
| BGP Config | ⏳ Planned |

---

## 🔧 Cilium Configuration

**Current Config** (`/var/lib/rancher/rke2/server/manifests/rke2-cilium-config.yaml`):

```yaml
# CNI: Cilium via RKE2
# BGP Mode: Native
# Features:
- kube-proxy Replacement (eBPF)
- Hubble Observability
- BGP Control Plane (enabled, not configured yet)
- LoadBalancer (hybrid mode)
```

### 📝 Notes

**Kernel Modules:**
- `vxlan`, `geneve`, `ip_tunnel` are REQUIRED
- Must be loaded before RKE2 starts
- Missing modules = BPF compilation errors

---

## 🎯 Roadmap

- [x] RKE2 3-Node HA Cluster
- [x] Cilium CNI with BGP
- [x] Hubble Observability
- [x] ArgoCD Installation
- [ ] Longhorn Storage
- [ ] Multus Multi-NIC
- [ ] KubeVirt VM Support
- [ ] KubeVirt OPNsense VM
- [ ] BGP Peering with OPNsense
- [ ] Application Deployments

---
