#!/bin/bash
# scripts/03-install-argocd.sh
# Install ArgoCD on RKE2 cluster with Cilium
# Run ONLY on Host03 (after RKE2+Cilium is running)

set -e

echo "🎯 Installing ArgoCD..."

# 1. Create namespace
echo "📦 Creating argocd namespace..."
kubectl create namespace argocd

# 2. Install ArgoCD
echo "📦 Installing ArgoCD (stable)..."
kubectl apply -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml

# 3. Wait for ArgoCD to be ready
echo "⏳ Waiting for ArgoCD pods to be ready (this may take 2-3 minutes)..."
kubectl wait --for=condition=Ready pods --all -n argocd --timeout=300s

# 4. Create Helm Repository Secrets
echo "📦 Creating Helm repository secrets..."
kubectl apply -f - <<'EOF'
---
apiVersion: v1
kind: Secret
metadata:
  name: cilium-helm-repo
  namespace: argocd
  labels:
    argocd.argoproj.io/secret-type: repository
stringData:
  type: helm
  name: cilium
  url: https://helm.cilium.io
  enableOCI: "false"
---
apiVersion: v1
kind: Secret
metadata:
  name: longhorn-helm-repo
  namespace: argocd
  labels:
    argocd.argoproj.io/secret-type: repository
stringData:
  type: helm
  name: longhorn
  url: https://charts.longhorn.io
  enableOCI: "false"
---
apiVersion: v1
kind: Secret
metadata:
  name: kubevirt-helm-repo
  namespace: argocd
  labels:
    argocd.argoproj.io/secret-type: repository
stringData:
  type: helm
  name: kubevirt
  url: https://kubevirt.github.io/kubevirt-charts
  enableOCI: "false"
EOF

echo "✅ Helm repository secrets created!"

# 5. Get initial admin password
ADMIN_PASSWORD=$(kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d)

# 6. Display results
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "✅ ArgoCD Installation Complete!"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "📊 ArgoCD Pods:"
kubectl get pods -n argocd
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "🔑 ArgoCD Admin Credentials:"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "   Username: admin"
echo "   Password: $ADMIN_PASSWORD"
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "🌐 Access ArgoCD UI:"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "1. Start port-forward:"
echo "   kubectl port-forward svc/argocd-server -n argocd 8080:443 --address=0.0.0.0 &"
echo ""
echo "2. Access in browser:"
echo "   https://10.0.200.103:8080"
echo ""
echo "3. Login with credentials above"
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "Next Steps:"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo ""
echo "1. Bootstrap ArgoCD:"
echo "   kubectl apply -f bootstrap/root-app.yaml"
echo ""
echo "   OR if using direct curl:"
echo "   kubectl apply -f https://raw.githubusercontent.com/Berndinox/k8s-homelab-gitops/main/bootstrap/root-app.yaml"
echo ""
echo "2. Watch deployment:"
echo "   kubectl get applications -n argocd -w"
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"