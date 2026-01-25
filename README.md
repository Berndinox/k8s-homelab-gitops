# k8s-homelab-gitops

GitOps-managed Kubernetes homelab cluster mit RKE2, Cilium CNI und ArgoCD.

## 🎯 Cluster Overview

**Infrastructure:**
- 3x Control-Plane Nodes (Ubuntu 24.04 LTS)
- RKE2 Kubernetes Distribution
- High Availability etcd
- Cilium CNI mit BGP Control Plane
- GitOps via ArgoCD

**Network Architecture:**
```
3x Ubuntu 24.04 Hosts (host01, host02, host03)
├── Management: VLAN 200 (10.0.200.0/24) - eno1
├── Cluster: VLAN 100 (10.0.100.0/24) - bond0 (LACP 20Gbit)
├── Pod Network: 10.1.0.0/16 (Cilium VXLAN)
├── Service Network: 10.2.0.0/16
└── LoadBalancer Pool: 10.0.200.0/24 (BGP announced)

Application VLANs: 5, 10, 30, 40, 50, 60, 100, 200
```

---

## 🚀 Installation

### Prerequisites

**Auf ALLEN Nodes ausführen:**

```bash
# 2. OS Preparation (WICHTIG - lädt Kernel Module!)
./scripts/01-os-prep.sh
```

Das `01-os-prep.sh` Script:
- Lädt Kernel Module (vxlan, geneve, ip_tunnel)
- Konfiguriert System Settings
- Macht Module persistent

### Step 1: Bootstrap First Node (host03)

```bash
# Auf host01:
cd scripts/
chmod +x *.sh

# OS Prep (falls nicht schon gemacht)
./01-os-prep.sh

# RKE2 + Cilium installieren
./02-install-rke2-cilium.sh

# Warten (~5 Minuten)
# Script installiert:
# - RKE2 
# - Cilium CNI (via HelmChartConfig)
# - kubectl setup

# Join Token speichern:
cat /var/lib/rancher/rke2/server/node-token
```

**Verification:**
```bash
kubectl get nodes
# NAME     STATUS   ROLES                 AGE   VERSION
# host01   Ready    control-plane,etcd    5m    v1.34.3+rke2r1

kubectl get pods -n kube-system -l k8s-app=cilium
# NAME           READY   STATUS    RESTARTS   AGE
# cilium-xxxxx   1/1     Running   0          3m
```

### Step 2: Join Additional Nodes (host02, host03)

```bash
# Auf host02 und host03:

# 1. OS Prep (falls nicht schon gemacht)
./scripts/01-os-prep.sh

# 2. Join Script vorbereiten
nano scripts/04-join-control-plane.sh

# Anpassen:
NODE_IP="10.0.100.102"              # host01: .101, host02: .102
NODE_NAME="host02"                  # hostname
JOIN_TOKEN=""     # Token von host01!

# 3. Ausführen:
./scripts/04-join-control-plane.sh
```

**Nach allen 3 Nodes:**
```bash
kubectl get nodes
# NAME     STATUS   ROLES                 AGE   VERSION
# host01   Ready    control-plane,etcd    5m   v1.34.3+rke2r1
# host02   Ready    control-plane,etcd    15m    v1.34.3+rke2r1
# host03   Ready    control-plane,etcd    25m   v1.34.3+rke2r1

kubectl get pods -n kube-system -l k8s-app=cilium
# Sollte 3 Pods zeigen (einer pro Node)
```

### Step 3: Deploy ArgoCD

```bash
./scripts/03-install-argocd.sh

# Warten bis alle Pods ready:
kubectl get pods -n argocd -w
```

**ArgoCD UI Access:**
```bash
# Port-forward:
kubectl port-forward svc/argocd-server -n argocd 8080:443 --address=0.0.0.0

# URL: https://10.0.200.103:8080
# User: admin
# Password:
kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d
```

### Step 4: Bootstrap GitOps

```bash
# ArgoCD Root App deployen
kubectl apply -f bootstrap/root-app.yaml

# Deployment watchen
kubectl get applications -n argocd -w
```

---

## 📦 Stack Components

### Layer 1: Infrastructure (Manual Installation)

| Component | Status | Notes |
|-----------|--------|-------|
| RKE2 | ✅ Installed | Via install script |
| Cilium CNI | ✅ Installed | VXLAN overlay, BGP enabled |
| ArgoCD | ✅ Installed | Via install script |

### Layer 2: GitOps Managed (via ArgoCD)

| Component | Status | Purpose |
|-----------|--------|---------|
| Namespaces | ✅ Done | Base namespaces |
| Longhorn | ⏳ Planned | Distributed storage |
| Multus | ⏳ Planned | Multi-NIC / VLAN support |
| KubeVirt | ⏳ Planned | VM workloads |
| BGP Config | ⏳ Planned | LoadBalancer IP announcements |
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

---

## 📁 Repository Structure

```
k8s-homelab-gitops/
├── scripts/
│   ├── 00-os-cleanup-host.sh          # Optional: Clean fresh install
│   ├── 01-os-prep.sh                  # OS prep + kernel modules
│   ├── 02-install-rke2-cilium.sh      # Bootstrap first node
│   ├── 03-install-argocd.sh           # Install ArgoCD
│   └── 04-join-control-plane.sh       # Join additional nodes
├── bootstrap/
│   └── root-app.yaml                  # ArgoCD App-of-Apps
├── infrastructure/
│   ├── namespaces/
│   ├── longhorn/
│   ├── multus/
│   └── kubevirt/
├── apps/
│   └── (application workloads)
└── docs/
    └── INSTALL-GUIDE.md               # Detailed installation guide
```

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

## 🔗 Quick Commands

```bash
# Cluster Info
kubectl cluster-info

# All Nodes
kubectl get nodes -o wide

# All Pods
kubectl get pods -A

# Cilium Status
cilium status  # (requires cilium CLI)

# ArgoCD Apps
kubectl get applications -n argocd
```

---

## 📝 Notes


**Kernel Modules:**
- `vxlan`, `geneve`, `ip_tunnel` are REQUIRED
- Must be loaded before RKE2 starts
- Missing modules = BPF compilation errors

---

## 🆘 Support

Bei Problemen:
1. Check logs: `kubectl logs -n kube-system -l k8s-app=cilium`
2. Check [docs/INSTALL-GUIDE.md](./docs/INSTALL-GUIDE.md)

---

**Status:** ✅ Cluster Running | 🚧 GitOps Setup In Progress