#!/bin/bash
# 00-cleanup-host.sh - Complete RKE2/Kubernetes cleanup

set -e

echo "🧹 Starting complete Kubernetes cleanup..."
echo "⚠️  This will remove ALL Kubernetes components!"


# 1. Stop services
echo "🛑 Stopping services..."
systemctl stop rke2-server 2>/dev/null || true
systemctl disable rke2-server 2>/dev/null || true
systemctl stop containerd 2>/dev/null || true

# 2. Kill processes
echo "🔪 Killing processes..."
pkill -9 -f rke2 2>/dev/null || true
pkill -9 -f containerd 2>/dev/null || true
pkill -9 -f kubelet 2>/dev/null || true
pkill -9 -f cilium 2>/dev/null || true
pkill -9 -f containerd-shim 2>/dev/null || true

# 3. Unmount filesystems
echo "📁 Unmounting filesystems..."
umount -l /run/k3s/containerd 2>/dev/null || true
umount -A /run/k3s 2>/dev/null || true
umount $(mount | grep '/var/lib/kubelet' | awk '{print $3}') 2>/dev/null || true
umount $(mount | grep '/var/lib/rancher' | awk '{print $3}') 2>/dev/null || true

# 4. Remove directories
echo "🗑️  Removing directories..."
rm -rf /var/lib/rancher/rke2
rm -rf /etc/rancher/rke2
rm -rf /var/lib/kubelet
rm -rf /etc/cni
rm -rf /opt/cni
rm -rf /run/k3s
rm -rf ~/.kube
rm -rf /var/lib/cni
rm -rf /var/log/pods
rm -rf /var/log/containers

# 5. Clean iptables
echo "🔥 Cleaning iptables..."
iptables -F 2>/dev/null || true
iptables -t nat -F 2>/dev/null || true
iptables -t mangle -F 2>/dev/null || true
iptables -X 2>/dev/null || true

# 6. Remove network interfaces
echo "🌐 Cleaning network interfaces..."
ip link | grep -E 'veth|cilium|lxc|cni' | awk '{print $2}' | sed 's/@.*//' | sed 's/://' | while read iface; do
    ip link delete "$iface" 2>/dev/null || true
done

# 7. Verification
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "✅ Cleanup Complete!"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "🔍 Remaining processes:"
ps aux | grep -E "rke2|containerd|kubelet|cilium" | grep -v grep || echo "   None - Clean!"
echo ""
echo "📁 Remaining directories:"
ls -d /var/lib/rancher /etc/rancher /var/lib/kubelet 2>/dev/null || echo "   None - Clean!"
echo ""
echo "✅ System is clean and ready for fresh installation!"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"