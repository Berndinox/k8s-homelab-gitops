# Applications

This directory contains application deployments managed by ArgoCD.

## Deployment

Apps are deployed **after infrastructure is healthy** (sync wave 10).

## Adding Applications

### Option 1: Direct Manifests

```bash
cd apps/
mkdir my-app
cd my-app/

# Add Kubernetes manifests
cat > deployment.yaml <<EOF
apiVersion: apps/v1
kind: Deployment
metadata:
  name: my-app
  namespace: default
spec:
  replicas: 3
  selector:
    matchLabels:
      app: my-app
  template:
    metadata:
      labels:
        app: my-app
    spec:
      containers:
      - name: app
        image: nginx:latest
        ports:
        - containerPort: 80
EOF

# Commit
git add .
git commit -m "Add my-app"
git push
```

ArgoCD syncs automatically.

### Option 2: Helm Chart

Create `apps/my-helm-app/application.yaml`:

```yaml
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: my-helm-app
  namespace: argocd
  annotations:
    argocd.argoproj.io/sync-wave: "10"
spec:
  project: default
  source:
    repoURL: https://charts.example.com
    chart: my-chart
    targetRevision: 1.0.0
  destination:
    server: https://kubernetes.default.svc
    namespace: my-app
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
    syncOptions:
      - CreateNamespace=true
```

### Option 3: Kustomize

```bash
cd apps/my-kustomize-app/
kustomize create
# Add your kustomization.yaml

git add .
git commit -m "Add kustomize app"
git push
```

## Monitoring

```bash
# Check all applications
kubectl get applications -n argocd

# Watch app deployment
kubectl get pods -A -w

# Check specific app
kubectl describe application apps -n argocd
```

## Notes

- Apps deploy **only after** infrastructure is healthy
- All apps auto-sync from Git
- Use namespaces to organize apps
- Storage via Longhorn (deployed in infrastructure wave 1)
