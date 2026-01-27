# Kubernetes Homelab Installation Guide

Complete installation guide for 3-node RKE2 cluster with Cilium, Longhorn, Multus, and KubeVirt.

## Prerequisites

- 3x Ubuntu 24.04 LTS hosts
- Mellanox ConnectX-3 (2x 10G ports) per host
- Management NIC (1G) per host
- LACP Bond configured (see Network Setup)

## Architecture

```
3x Hosts (host01, host02, host03)
├── Management: VLAN 200 (eno1) - 1G
├── Cluster: VLAN 100 (bond0) - 20G LACP
└── Application VLANs: 5, 10, 30, 40, 50, 60, 100, 200
```

---

## Installation Methods

### Method A: Using Git Clone (Development)

**On each host:**

```bash
cd ~
git clone https://github.com/Berndinox/k8s-homelab-gitops.git
cd k8s-homelab-gitops
```

Then follow the steps below, using local scripts.

### Method B: Direct Curl (Production - Recommended)

Use curl commands directly without cloning the repo.

---

## Step-by-Step Installation

### 1. Network Setup

**On ALL hosts - configure LACP Bond + VLANs:**

```bash
# Create netplan config
sudo tee /etc/netplan/01-network.yaml > /dev/null << 'EOF'
network:
  version: 2
  renderer: networkd
  ethernets:
    enp1s0:
      dhcp4: no
      dhcp6: no
      optional: true
    enp1s0d1:
      dhcp4: no
      dhcp6: no
      optional: true
    eno1:
      dhcp4: yes
  bonds:
    bond0:
      interfaces:
        - enp1s0
        - enp1s0d1
      parameters:
        mode: 802.3ad
        lacp-rate: fast
        mii-monitor-interval: 100
        transmit-hash-policy: layer3+4
      dhcp4: no
      dhcp6: no
  vlans:
    vlan5:
      id: 5
      link: bond0
    vlan10:
      id: 10
      link: bond0
    vlan30:
      id: 30
      link: bond0
    vlan40:
      id: 40
      link: bond0
    vlan50:
      id: 50
      link: bond0
    vlan60:
      id: 60
      link: bond0
    vlan100:
      id: 100
      link: bond0
      addresses:
        - 10.0.100.101/24  # Host01: .101, Host02: .102, Host03: .103
    vlan200:
      id: 200
      link: bond0
EOF

sudo netplan apply
```

---

### 2. OS Preparation (ALL 3 hosts!)

**Run on Host01, Host02, AND Host03:**

```bash
# Method A (Git Clone):
sudo ./scripts/01-os-prep.sh

# Method B (Direct Curl):
curl -sSL https://raw.githubusercontent.com/Berndinox/k8s-homelab-gitops/main/scripts/01-os-prep.sh | sudo bash
```

---

### 3. Install First Node (Host03)

**RKE2 + Cilium:**

```bash
# Method A:
sudo ./scripts/01-install-rke2-cilium.sh

# Method B:
curl -sSL https://raw.githubusercontent.com/Berndinox/k8s-homelab-gitops/main/scripts/01-install-rke2-cilium.sh | sudo bash
```

**Verify:**
```bash
kubectl get nodes
kubectl get pods -n kube-system -l app.kubernetes.io/name=cilium
```

**Save Join Token:**
```bash
sudo cat /var/lib/rancher/rke2/server/node-token > ~/join-token.txt
```

---

### 4. Install ArgoCD (Host03)

```bash
# Method A:
./scripts/02-install-argocd.sh

# Method B:
curl -sSL https://raw.githubusercontent.com/Berndinox/k8s-homelab-gitops/main/scripts/02-install-argocd.sh | bash
```

**Get Admin Password:**
```bash
kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d
echo
```

**Access UI:**
```bash
kubectl port-forward svc/argocd-server -n argocd 8080:443 --address=0.0.0.0
# https://10.0.200.103:8080
```

---

### 5. Bootstrap GitOps

```bash
# Method A:
kubectl apply -f bootstrap/root-app.yaml

# Method B:
kubectl apply -f https://raw.githubusercontent.com/Berndinox/k8s-homelab-gitops/main/bootstrap/root-app.yaml
```

**Watch deployment:**
```bash
kubectl get applications -n argocd -w
```

---

### 6. Join Additional Control Plane Nodes (Host01, Host02)

**On Host03, get the join token:**
```bash
sudo cat /var/lib/rancher/rke2/server/node-token
```

**Copy the token, then on Host01 and Host02:**

```bash
# Set variables
export JOIN_TOKEN=""
export SERVER_URL="https://10.0.100.103:9345"
export NODE_IP="10.0.100.101"  # Host01: .101, Host02: .102

# Method A (Git Clone):
sudo -E ./scripts/04-join-control-plane.sh

# Method B (Direct Curl):
curl -sSL https://raw.githubusercontent.com/Berndinox/k8s-homelab-gitops/main/scripts/04-join-control-plane.sh | \
  SERVER_URL=$SERVER_URL JOIN_TOKEN=$JOIN_TOKEN NODE_IP=$NODE_IP sudo -E bash
```

**Verify 3-node cluster:**
```bash
# On any node
kubectl get nodes
# Should show: host01, host02, host03 (all as control-plane,etcd,master)

kubectl get pods -n kube-system -l component=etcd
# Should show: 3 etcd pods
```

---

## Verification

### Cluster Status
```bash
kubectl get nodes -o wide
kubectl get pods -A
```

### Cilium Status
```bash
kubectl get pods -n kube-system -l app.kubernetes.io/name=cilium
```

### ArgoCD Applications
```bash
kubectl get applications -n argocd
```

### Longhorn (once deployed via ArgoCD)
```bash
kubectl get pods -n longhorn-system
```

---

## Troubleshooting

### Node Not Ready
```bash
kubectl describe node 
kubectl get pods -n kube-system
```

### Cilium Issues
```bash
kubectl logs -n kube-system -l app.kubernetes.io/name=cilium
cilium status  # if cilium CLI installed
```

### ArgoCD Sync Issues
```bash
kubectl describe application  -n argocd
kubectl logs -n argocd -l app.kubernetes.io/name=argocd-repo-server
```

---

## Clean Reinstall

If you need to start over on any host:

```bash
# Method A (Git Clone):
sudo ./scripts/00-cleanup-host.sh

# Method B (Direct Curl):
curl -sSL https://raw.githubusercontent.com/Berndinox/k8s-homelab-gitops/main/scripts/00-cleanup-host.sh | sudo bash
```

Then start from **Step 3** (Install RKE or 04 "Join Cluster") again.



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
