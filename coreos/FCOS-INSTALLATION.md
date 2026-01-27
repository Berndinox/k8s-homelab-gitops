# Fedora CoreOS Kubernetes Homelab - Installation Guide

Complete guide for installing a 3-node RKE2 Kubernetes cluster on Fedora CoreOS using Ignition/Butane configuration and USB boot.

## Overview

This guide covers:
- Preparing Butane configs with your credentials
- Converting Butane to Ignition
- Creating bootable USB sticks with embedded configs
- Installing all three nodes
- Deploying ArgoCD for GitOps

## Architecture

```
3x Fedora CoreOS Hosts (host01, host02, host03)
├── Management: DHCP via eno1
├── Cluster: VLAN 100 (bond0) - 20G LACP
│   ├── host01: 10.0.100.101
│   ├── host02: 10.0.100.102
│   └── host03: 10.0.100.103
├── Pod Network: 10.1.0.0/16 (Cilium VXLAN)
└── Service Network: 10.2.0.0/16
```

---

## Prerequisites

### Hardware
- 3x Bare-metal servers
- 2x 10G NICs per host (for LACP bond)
- 1x Management NIC per host
- 3x USB sticks (8GB+)

### Software Requirements
- Linux/macOS workstation (for preparing configs)
- Butane CLI tool
- coreos-installer
- Internet access

---

## Step 1: Prepare Your Environment

### Install Required Tools

**On Linux:**
```bash
# Install Butane
VERSION="0.20.0"
curl -L "https://github.com/coreos/butane/releases/download/v${VERSION}/butane-x86_64-unknown-linux-gnu" \
  -o /usr/local/bin/butane
chmod +x /usr/local/bin/butane

# Install coreos-installer
VERSION="0.21.0"
curl -L "https://github.com/coreos/coreos-installer/releases/download/v${VERSION}/coreos-installer-x86_64-unknown-linux-gnu" \
  -o /usr/local/bin/coreos-installer
chmod +x /usr/local/bin/coreos-installer
```

**On macOS:**
```bash
# Install Butane
brew install butane

# Install coreos-installer
brew install coreos-installer
```

### Download Fedora CoreOS ISO

```bash
# Create working directory
mkdir -p ~/fcos-install && cd ~/fcos-install

# Download latest stable ISO
coreos-installer download -s stable -p metal -f iso

# Should download: fedora-coreos-<version>-live.x86_64.iso
```

---

## Step 2: Customize Butane Configs

### Update SSH Keys and Passwords

**Generate SSH key (if needed):**
```bash
ssh-keygen -t rsa -b 4096 -C "homelab-cluster"
cat ~/.ssh/id_rsa.pub
```

**Generate password hash:**
```bash
# Install mkpasswd if needed via package manager
# Example: brew install mkpasswd (macOS)

# Generate hash (example password: "fedora")
mkpasswd -m sha-512
# Copy the output to replace password_hash in configs
```

### Edit All Three Butane Files

Edit the following in all three configs (`fcos-host0[1-3]*.bu`):

```yaml
passwd:
  users:
    - name: core
      password_hash: "$6$YOUR_GENERATED_HASH_HERE"  # Replace with your hash
      ssh_authorized_keys:
        - "ssh-rsa YOUR_PUBLIC_KEY_HERE"  # Replace with your public key
```

**Files to edit:**
- `fcos-host03-bootstrap.bu` (Bootstrap node)
- `fcos-host01-join.bu` (Join node)
- `fcos-host02-join.bu` (Join node)

---

## Step 3: Install Bootstrap Node (host03)

### Convert Butane to Ignition

```bash
cd ~/fcos-install

# Convert host03 config
butane --pretty --strict \
  k8s-homelab-gitops/coreos/fcos-host03-bootstrap.bu \
  > host03.ign

# Verify JSON output
cat host03.ign | jq . | head -20
```

### Create Bootable USB with Embedded Config

```bash
# Identify your USB device
lsblk
# Example: /dev/sdb (Linux) or /dev/disk2 (macOS)

# WARNING: This will ERASE the USB drive!
# Replace /dev/sdX with your USB device
sudo coreos-installer install /dev/sdX \
  --image-file fedora-coreos-*-live.x86_64.iso \
  --ignition-file host03.ign

# Wait for completion (~5 minutes)
```

### Boot and Install host03

1. Insert USB into host03
2. Boot from USB (F11/F12 for boot menu)
3. Fedora CoreOS will:
   - Boot from USB
   - Read embedded Ignition config
   - Install to disk
   - Apply configuration
   - Reboot automatically

4. After reboot (remove USB):
   - Wait ~10-15 minutes for RKE2 installation
   - System will automatically:
     - Load kernel modules
     - Configure network (LACP bond + VLANs)
     - Install RKE2
     - Start Kubernetes cluster
     - Deploy Cilium CNI

### Verify Bootstrap Node

**Login via SSH:**
```bash
ssh core@10.0.100.103
# or via management interface
ssh core@<management-ip>
```

**Check system status:**
```bash
# Check hostname
hostnamectl

# Check network (bond + VLAN)
ip a show bond0
ip a show vlan100

# Check RKE2 installation
sudo systemctl status rke2-server

# Check Kubernetes
kubectl get nodes
# Expected: host03 Ready control-plane,etcd,master

# Check Cilium
kubectl get pods -n kube-system -l k8s-app=cilium
# Expected: 1 cilium pod running

# Get join token for other nodes
sudo cat /var/lib/rancher/rke2/server/node-token
# Save this token - you'll need it for host01 and host02!
```

**Example token:**
```
K10abc123def456ghi789jkl012mno345pqr678stu901vwx234yz::server:a1b2c3d4e5f6
```

---

## Step 4: Install Join Nodes (host01 & host02)

### Update Join Configs with Token

**Edit both files:**
- `fcos-host01-join.bu`
- `fcos-host02-join.bu`

Replace this line:
```yaml
token: JOIN_TOKEN_PLACEHOLDER
```

With your actual token from host03:
```yaml
token: K10abc123def456ghi789jkl012mno345pqr678stu901vwx234yz::server:a1b2c3d4e5f6
```

### Create USB for host01

```bash
# Convert to Ignition
butane --pretty --strict \
  k8s-homelab-gitops/coreos/fcos-host01-join.bu \
  > host01.ign

# Create bootable USB
sudo coreos-installer install /dev/sdX \
  --image-file fedora-coreos-*-live.x86_64.iso \
  --ignition-file host01.ign
```

### Install host01

1. Insert USB into host01
2. Boot from USB
3. Wait for installation and reboot
4. Remove USB after reboot
5. Wait ~10 minutes for join process

### Create USB for host02

```bash
# Convert to Ignition
butane --pretty --strict \
  k8s-homelab-gitops/coreos/fcos-host02-join.bu \
  > host02.ign

# Create bootable USB
sudo coreos-installer install /dev/sdX \
  --image-file fedora-coreos-*-live.x86_64.iso \
  --ignition-file host02.ign
```

### Install host02

1. Insert USB into host02
2. Boot from USB
3. Wait for installation and reboot
4. Remove USB after reboot
5. Wait ~10 minutes for join process

### Verify Cluster

**SSH to any node:**
```bash
ssh core@10.0.100.103  # or .101, .102
```

**Check cluster status:**
```bash
# All nodes should be Ready
kubectl get nodes -o wide
# Expected output:
# NAME     STATUS   ROLES                       AGE   VERSION
# host01   Ready    control-plane,etcd,master   5m    v1.34.3+rke2r1
# host02   Ready    control-plane,etcd,master   3m    v1.34.3+rke2r1
# host03   Ready    control-plane,etcd,master   15m   v1.34.3+rke2r1

# Check etcd (3-node HA)
kubectl get pods -n kube-system -l component=etcd
# Expected: 3 etcd pods (one per node)

# Check Cilium (should have 3 pods)
kubectl get pods -n kube-system -l k8s-app=cilium -o wide
# Expected: 3 cilium pods (one per node)

# Check all system pods
kubectl get pods -A
```

---

## Step 5: Install ArgoCD

ArgoCD installation still uses the original script (compatible with any Kubernetes):

**On any node (host03 recommended):**

```bash
# Method 1: Direct curl
curl -sSL https://raw.githubusercontent.com/Berndinox/k8s-homelab-gitops/main/coreos/03-install-argocd.sh | bash

# Method 2: If repo is cloned
cd ~/k8s-homelab-gitops
./coreos/03-install-argocd.sh
```

**Get ArgoCD password:**
```bash
kubectl -n argocd get secret argocd-initial-admin-secret \
  -o jsonpath="{.data.password}" | base64 -d
echo
```

**Access ArgoCD UI:**
```bash
# Port-forward
kubectl port-forward svc/argocd-server -n argocd 8080:443 --address=0.0.0.0

# Open browser: https://10.0.100.103:8080
# Username: admin
# Password: <from previous command>
```

---

## Step 6: Bootstrap GitOps

**Deploy ArgoCD root application:**

```bash
kubectl apply -f https://raw.githubusercontent.com/Berndinox/k8s-homelab-gitops/main/bootstrap/root-app.yaml

# Watch deployment
kubectl get applications -n argocd -w
```

---

## Troubleshooting

### Node Won't Boot
- Check BIOS boot order
- Verify USB was created correctly
- Check UEFI vs Legacy boot mode

### Network Not Working
- Verify interface names (`enp1s0`, `enp1s0d1`, `eno1`)
  - Run `ip a` during install
  - Update NetworkManager configs if different
- Check switch LACP configuration
- Verify VLAN 100 is allowed on trunk port

### RKE2 Won't Start
```bash
# Check service status
sudo systemctl status rke2-server

# Check logs
sudo journalctl -u rke2-server -f

# Verify kernel modules
lsmod | grep -E "vxlan|geneve|overlay"

# Check config
sudo cat /etc/rancher/rke2/config.yaml
```

### Cilium Issues
```bash
# Check Cilium pods
kubectl get pods -n kube-system -l k8s-app=cilium

# Check Cilium logs
kubectl logs -n kube-system -l k8s-app=cilium --tail=100

# Restart Cilium
kubectl delete pods -n kube-system -l k8s-app=cilium
```

### Join Token Invalid
- Token expires after 12 hours
- Regenerate on host03: `sudo kubeadm token create --print-join-command`
- Or get from: `sudo cat /var/lib/rancher/rke2/server/node-token`

### SSH Access Issues
```bash
# Login via console (physical/IPMI)
# Check SSH service
sudo systemctl status sshd

# Check firewall (should be open by default)
sudo firewall-cmd --list-all

# Verify SSH key
cat ~/.ssh/authorized_keys
```

---

## Maintenance

### Update Fedora CoreOS

```bash
# Enable updates
sudo rpm-ostree upgrade

# Reboot (do one node at a time!)
sudo systemctl reboot
```

### Backup Important Files

```bash
# RKE2 config
sudo tar czf rke2-backup.tar.gz \
  /etc/rancher/rke2/ \
  /var/lib/rancher/rke2/server/token

# Copy to safe location
scp rke2-backup.tar.gz user@backup-server:/backups/
```

### Reset a Node

To reinstall a node from scratch:

1. Boot from USB with new Ignition config
2. RKE2 will automatically rejoin cluster
3. No manual steps needed

---

## Resources

- [Fedora CoreOS Documentation](https://docs.fedoraproject.org/en-US/fedora-coreos/)
- [Butane Config Spec](https://coreos.github.io/butane/config-fcos-v1_5/)
- [RKE2 Documentation](https://docs.rke2.io/)
- [Cilium Documentation](https://docs.cilium.io/)

---

**Questions or issues?** Open an issue in the repository.
