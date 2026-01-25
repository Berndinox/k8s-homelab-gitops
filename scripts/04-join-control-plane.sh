#!/bin/bash
# 03-join-node.sh - Join additional nodes to RKE2 cluster

set -e

# Check required environment variables
if [ -z "$SERVER_URL" ] || [ -z "$JOIN_TOKEN" ] || [ -z "$NODE_IP" ]; then
    echo "❌ Error: Required environment variables not set!"
    echo ""
    echo "Usage:"
    echo "  export SERVER_URL=\"https://10.0.100.103:9345\""
    echo "  export JOIN_TOKEN=\"<token-from-first-node>\""
    echo "  export NODE_IP=\"10.0.100.101\"  # or .102"
    echo "  sudo -E ./03-join-node.sh"
    echo ""
    exit 1
fi

NODE_NAME=$(hostname)

echo "🔗 Joining $NODE_NAME ($NODE_IP) to cluster..."
echo "   Server: $SERVER_URL"

# 1. Install RKE2
echo "📦 Installing RKE2..."
curl -sfL https://get.rke2.io | sh

# 2. Create RKE2 config for joining
echo "⚙️  Creating RKE2 join configuration..."
mkdir -p /etc/rancher/rke2

tee /etc/rancher/rke2/config.yaml > /dev/null <<EOF
# Join to existing cluster
server: $SERVER_URL
token: $JOIN_TOKEN

# Node Configuration
node-ip: $NODE_IP
advertise-address: $NODE_IP

# Network Configuration (must match first node!)
cluster-cidr: 10.1.0.0/16
service-cidr: 10.2.0.0/16
cluster-dns: 10.2.0.10

# NO CNI (Cilium already deployed)
cni: none

# Disable unnecessary components
disable:
  - rke2-ingress-nginx

# TLS SANs
tls-san:
  - host01
  - host02
  - host03
  - 10.0.200.101
  - 10.0.200.102
  - 10.0.200.103
  - 10.0.100.101
  - 10.0.100.102
  - 10.0.100.103

# Metrics
etcd-expose-metrics: true
EOF

# 3. Start RKE2
echo "🚀 Starting RKE2..."
systemctl enable rke2-server.service
systemctl start rke2-server.service

echo "⏳ Waiting for RKE2 to join cluster (60 seconds)..."
sleep 60

# 4. Setup kubectl (optional, usually done on first node)
echo "🔧 Setting up kubectl..."
mkdir -p ~/.kube
cp /etc/rancher/rke2/rke2.yaml ~/.kube/config
chown $(id -u):$(id -g) ~/.kube/config
ln -sf /var/lib/rancher/rke2/bin/kubectl /usr/local/bin/kubectl

# 5. Verification
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "✅ Node Join Complete!"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "📊 Cluster Nodes (from first node):"
kubectl get nodes -o wide 2>/dev/null || echo "   Run 'kubectl get nodes' on first node to verify"
echo ""
echo "🐝 Cilium Pods:"
kubectl get pods -n kube-system -l app.kubernetes.io/name=cilium 2>/dev/null || echo "   Check on first node"
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "Note: Run on FIRST node to see full cluster status"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"