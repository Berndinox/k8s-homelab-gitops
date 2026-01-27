# k8s-homelab-gitops

GitOps-managed Kubernetes homelab cluster mit RKE2, Cilium CNI und ArgoCD.

**Disclaimer**: Dieses Projekt wird „as is“ bereitgestellt. Es handelt sich um ein privates Hobbyprojekt ohne Garantie auf Funktion oder Sicherheit. Der Autor übernimmt keine Haftung für Schäden, die durch die Nutzung entstehen.

## 🎯 Cluster Overview

**Infrastructure:**
- 3x Control-Plane Nodes (CoreOS)
- RKE2 Kubernetes Distribution
- High Availability etcd
- Cilium CNI mit BGP Control Plane
- KubeVirt und Multus für erweitertes Networking
- GitOps via ArgoCD

**Network Architecture:**
```
3x Ubuntu 24.04 Hosts (host01, host02, host03)
├── Management: VLAN 200 (10.0.200.0/24)
├── Workload: VLAN 5, 10, 20, 30, 40, 50, 60, 70, 80, 90, 100 (10.0.100.0/24) - bond0 (LACP Trunk Port 20Gbit)
├── Pod Network: 10.1.0.0/16 (Cilium VXLAN)
└── Service Network: 10.2.0.0/16
```

---

## 📁 Repository Structure
In logischer Reihenfolge, von Bare-Metall installation zu GitOps.

```
k8s-homelab-gitops/
├── coreos/
├── argocd-apps/
├── bootstrap/
├── infrastructure/
└── apps/
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

**Aktuelle Config** (`/var/lib/rancher/rke2/server/manifests/rke2-cilium-config.yaml`):

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
- [x] Cilium CNI mit BPG
- [x] Hubble Observability
- [x] ArgoCD Installation
- [ ] Longhorn Storage
- [ ] Multus Multi-NIC
- [ ] KubeVirt VM Support
- [ ] KubeVirt OPNSense VM
- [ ] BGP Peering mit OPNsense
- [ ] Application Deployments

---




---
