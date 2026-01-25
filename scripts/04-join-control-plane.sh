#!/bin/bash
# scripts/02-join-rke2-server.sh
# Join additional server nodes to RKE2 cluster
# Run on Host01 or Host02 to join the cluster as control-plane

set -e

# Variables - ADJUST FOR EACH HOST!
NODE_IP="10.0.100.101"          # Host01: .101, Host02: .102
NODE_NAME="host01"              # host01 or host02
CLUSTER_CIDR="10.1.0.0/16"
SERVICE_CIDR="10.2.0.0/16"

# Join Configuration - GET FROM HOST03!
FIRST_SERVER_IP="10.0.100.103"  # IP of host03
JOIN_TOKEN="<PASTE_TOKEN_HERE>"  # Get from host03: cat /var/lib/rancher/rke2/server/node-token

echo "🚀 Joining RKE2 Cluster on $NODE_NAME ($NODE_IP)"

# Validate token
if [ "$JOIN_TOKEN" == "<PASTE_TOKEN_HERE>" ]; then
  echo "❌ ERROR: Please set JOIN_TOKEN first!"
  echo "   Get it from host03: cat /var/lib/rancher/rke2/server/node-token"
  exit 1
fi

# 1. Install RKE2
echo "📦 Installing RKE2..."
curl -sfL https://get.rke2.io | sh

# 2. Create RKE2 config for joining
echo "⚙️  Creating RKE2 configuration..."
mkdir -p /etc/rancher/rke2

tee /etc/rancher/rke2/config.yaml > /dev/null <<EOF
# Join existing cluster
server: https://$FIRST_SERVER_IP:9345
token: $JOIN_TOKEN

# Node Configuration
node-ip: $NODE_IP
advertise-address: $NODE_IP

# Network Configuration
cluster-cidr: $CLUSTER_CIDR
service-cidr: $SERVICE_CIDR
cluster-dns: 10.2.0.10

# CNI - Use RKE2's bundled Cilium
cni: cilium

# Disable unnecessary components
disable:
  - rke2-ingress-nginx
  - rke2-canal

# Disable kube-proxy (Cilium will replace it)
disable-kube-proxy: true
write-kubeconfig-mode: "0644"

# TLS SANs for all nodes
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

# 3. Create Cilium HelmChartConfig (same as first node)
echo "🐝 Creating Cilium HelmChartConfig..."
mkdir -p /var/lib/rancher/rke2/server/manifests/

tee /var/lib/rancher/rke2/server/manifests/rke2-cilium-config.yaml > /dev/null <<'EOF'
---
apiVersion: helm.cattle.io/v1
kind: HelmChartConfig
metadata:
  name: rke2-cilium
  namespace: kube-system
spec:
  valuesContent: |-
    # IPAM Configuration
    ipam:
      mode: kubernetes

    # Replace kube-proxy with eBPF
    kubeProxyReplacement: true
    k8sServiceHost: 127.0.0.1
    k8sServicePort: 6443

    # Operator Configuration
    operator:
      replicas: 1

    # Hubble Observability
    hubble:
      enabled: true
      relay:
        enabled: true
      ui:
        enabled: true
      metrics:
        enabled:
          - dns
          - drop
          - tcp
          - flow
          - icmp
          - http

    # BGP Control Plane
    bgpControlPlane:
      enabled: true

    # LoadBalancer
    externalIPs:
      enabled: true
    loadBalancer:
      mode: hybrid

    # Network Configuration
    enableIPv4Masquerade: true
    routingMode: native
    autoDirectNodeRoutes: true
    ipv4NativeRoutingCIDR: 10.1.0.0/16

    # BPF Configuration
    bpf:
      masquerade: true
EOF

# 4. Start RKE2 Server (will join cluster)
echo "🚀 Starting RKE2 and joining cluster..."
systemctl enable rke2-server.service
systemctl start rke2-server.service



# 5. Setup kubectl
echo "🔧 Setting up kubectl..."
mkdir -p ~/.kube
cp /etc/rancher/rke2/rke2.yaml ~/.kube/config
chown $(id -u):$(id -g) ~/.kube/config
ln -sf /var/lib/rancher/rke2/bin/kubectl /usr/local/bin/kubectl

# 6. Wait for API to be responsive
echo "⏳ Waiting for Kubernetes API..."
for i in {1..30}; do
  if kubectl get nodes &>/dev/null; then
    echo "✅ Kubernetes API is ready!"
    break
  fi
  echo "   Waiting for API... ($i/30)"
  sleep 5
done

# 7. Wait for this node to appear
echo "⏳ Waiting for $NODE_NAME to join..."
for i in {1..30}; do
  if kubectl get node $NODE_NAME &>/dev/null; then
    echo "✅ Node $NODE_NAME joined!"
    break
  fi
  echo "   Waiting for node... ($i/30)"
  sleep 10
done

# 8. Wait for node to be Ready
echo "⏳ Waiting for node to be Ready..."
for i in {1..30}; do
  NODE_STATUS=$(kubectl get node $NODE_NAME -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}' 2>/dev/null)
  if [ "$NODE_STATUS" == "True" ]; then
    echo "✅ Node is Ready!"
    break
  fi
  echo "   Waiting for Ready status... ($i/30)"
  sleep 10
done

# 9. Verification
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "✅ Node Join Complete!"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "📊 All Cluster Nodes:"
kubectl get nodes -o wide
echo ""
echo "🐝 Cilium Pods (should have 2+ now):"
kubectl get pods -n kube-system -l k8s-app=cilium -o wide
echo ""
echo "🎯 etcd Members:"
kubectl get pods -n kube-system -l component=etcd
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "Next steps:"
echo "1. Repeat for host02 if needed (3-node HA)"
echo "2. Verify cluster: kubectl get nodes"
echo "3. Check etcd: kubectl get pods -n kube-system -l component=etcd"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"