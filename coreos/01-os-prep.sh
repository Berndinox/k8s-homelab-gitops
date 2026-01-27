#!/bin/bash
# 00-os-prep.sh - OS preparation for RKE2 + KubeVirt

set -e

echo "🔧 Starting OS preparation for Kubernetes..."

# 1. System Update
echo "📦 Updating system..."
apt update && apt upgrade -y

# 2. Install required packages
echo "📦 Installing required packages..."
apt install -y \
    curl \
    wget \
    git \
    jq \
    iputils-ping \
    net-tools \
    qemu-kvm \
    libvirt-daemon-system \
    libvirt-clients \
    bridge-utils \
    cpu-checker \
    iptables \
    socat \
    conntrack \
    apparmor-utils \
    chrony

# 3. Kernel modules
echo "🔧 Configuring kernel modules..."
mkdir -p /etc/modules-load.d/

tee /etc/modules-load.d/kubernetes.conf > /dev/null << 'EOF'
overlay
br_netfilter
iptable_nat
ip_vs
ip_vs_rr
ip_vs_wrr
ip_vs_sh
nf_conntrack
vhost_net
vhost_vsock
vxlan
geneve
ip_tunnel
EOF

# Load modules now
modprobe overlay
modprobe br_netfilter
modprobe iptable_nat
modprobe ip_vs
modprobe ip_vs_rr
modprobe ip_vs_wrr
modprobe ip_vs_sh
modprobe nf_conntrack
modprobe vhost_net
modprobe vhost_vsock
modprobe vxlan
modprobe geneve
modprobe ip_tunnel

# 4. Sysctl settings
echo "🔧 Configuring sysctl..."
tee /etc/sysctl.d/99-kubernetes.conf > /dev/null << 'EOF'
# IP Forwarding
net.ipv4.ip_forward = 1
net.ipv6.conf.all.forwarding = 1

# Bridge netfilter
net.bridge.bridge-nf-call-iptables = 1
net.bridge.bridge-nf-call-ip6tables = 1

# Performance
net.ipv4.tcp_slow_start_after_idle = 0
net.core.rmem_max = 134217728
net.core.wmem_max = 134217728
net.ipv4.tcp_rmem = 4096 87380 67108864
net.ipv4.tcp_wmem = 4096 65536 67108864

# Connection tracking
net.netfilter.nf_conntrack_max = 1000000
net.netfilter.nf_conntrack_tcp_timeout_established = 86400

# ARP cache
net.ipv4.neigh.default.gc_thresh1 = 80000
net.ipv4.neigh.default.gc_thresh2 = 90000
net.ipv4.neigh.default.gc_thresh3 = 100000

# File limits
fs.inotify.max_user_instances = 8192
fs.inotify.max_user_watches = 524288
fs.file-max = 2097152
EOF

sysctl --system

# 5. Disable swap
echo "🔧 Disabling swap..."
swapoff -a
sed -i '/ swap / s/^/#/' /etc/fstab

# 6. NTP
echo "🕐 Configuring NTP..."
systemctl enable --now chrony

# 7. Libvirt for KubeVirt
echo "🖥️  Configuring libvirt..."
systemctl enable libvirtd
systemctl start libvirtd

# 8. Verification
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "✅ OS Preparation Complete!"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "🔍 Verification:"
echo ""
echo "KVM Support:"
kvm-ok
echo ""
echo "IP Forwarding: $(sysctl net.ipv4.ip_forward | awk '{print $3}')"
echo ""
echo "Loaded Modules:"
lsmod | grep -E "overlay|br_netfilter|ip_vs|vhost" | awk '{print "  - " $1}'
echo ""
echo "Swap Status:"
free -h | grep Swap
echo ""
echo "✅ System is ready for RKE2 installation!"