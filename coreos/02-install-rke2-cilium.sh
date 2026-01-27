#!/bin/bash
# scripts/02-install-rke2-cilium.sh
# Automated RKE2 + Cilium installation using HelmChartConfig (Option A - RECOMMENDED)
# Run ONLY on Host03 (first/bootstrap node)

set -e

# Variables - ADJUST FOR EACH HOST!
NODE_IP="10.0.100.103"          # Host03: .103, Host01: .101, Host02: .102
NODE_NAME="host03"              # host01, host02, host03
CLUSTER_CIDR="10.1.0.0/16"
SERVICE_CIDR="10.2.0.0/16"

echo "🚀 Installing RKE2 + Cilium on $NODE_NAME ($NODE_IP)"

# 1. Install RKE2
echo "📦 Installing RKE2..."
curl -sfL https://get.rke2.io | sh

# 2. Create RKE2 config
echo "⚙️  Creating RKE2 configuration..."
mkdir -p /etc/rancher/rke2

tee /etc/rancher/rke2/config.yaml > /dev/null <<EOF
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

# 3. Create Cilium HelmChartConfig for customization
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

# 4. Start RKE2 (will auto-deploy Cilium!)
echo "🚀 Starting RKE2 (Cilium will be deployed automatically)..."
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

# 7. Check if Cilium pods exist
echo "🔍 Checking Cilium deployment status..."
sleep 10

CILIUM_PODS=$(kubectl get pods -n kube-system -l k8s-app=cilium --no-headers 2>/dev/null | wc -l)

if [ "$CILIUM_PODS" -eq 0 ]; then
  echo "⚠️  No Cilium pods found yet, waiting for helm job to complete..."
  kubectl wait --for=condition=complete job/helm-install-rke2-cilium -n kube-system --timeout=300s || true
  sleep 20
fi

# 8. Restart Cilium pods (GitHub Issue #42179 solution)
echo "🐝 Restarting Cilium agents (fix for bootstrap issue)..."
kubectl delete pods -n kube-system -l k8s-app=cilium --ignore-not-found=true

echo "⏳ Waiting for Cilium to become ready..."
kubectl wait --for=condition=Ready pods -l k8s-app=cilium -n kube-system --timeout=300s

# 9. Wait for node to be Ready
echo "⏳ Waiting for node to be Ready..."
for i in {1..30}; do
  NODE_STATUS=$(kubectl get nodes -o jsonpath='{.items[0].status.conditions[?(@.type=="Ready")].status}' 2>/dev/null)
  if [ "$NODE_STATUS" == "True" ]; then
    echo "✅ Node is Ready!"
    break
  fi
  echo "   Waiting for node... ($i/30)"
  sleep 10
done

# 10. Verification
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "✅ Installation Complete!"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "📊 Node Status:"
kubectl get nodes -o wide
echo ""
echo "🐝 Cilium Pods:"
kubectl get pods -n kube-system -l k8s-app=cilium -o wide
echo ""
echo "📦 All System Pods:"
kubectl get pods -n kube-system
echo ""
echo "🔑 Join Token for other nodes:"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
cat /var/lib/rancher/rke2/server/node-token
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "Next steps:"
echo "1. Verify Cilium: cilium status (install cilium CLI first)"
echo "2. Install ArgoCD: ./scripts/03-install-argocd.sh"
echo "3. Bootstrap ArgoCD: kubectl apply -f bootstrap/root-app.yaml"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"