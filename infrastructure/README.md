# Infrastructure Components

This directory contains core infrastructure components deployed in sequence using ArgoCD sync waves.

## Deployment Order (Sync Waves)

Components are deployed in numbered order. Each must be healthy before the next begins.

```
Wave 0: 00-namespaces/     → Kubernetes namespaces
Wave 1: 01-longhorn/       → Persistent storage
Wave 2: 02-multus/         → Multi-NIC networking
Wave 3: 03-kubevirt/       → VM virtualization
```

## Adding Components

### Example: Add Longhorn via Helm

Create `01-longhorn/longhorn.yaml`:

```yaml
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: longhorn
  namespace: argocd
  annotations:
    argocd.argoproj.io/sync-wave: "1"
spec:
  project: default
  source:
    repoURL: https://charts.longhorn.io
    chart: longhorn
    targetRevision: 1.6.0
    helm:
      values: |
        defaultSettings:
          defaultReplicaCount: 3
  destination:
    server: https://kubernetes.default.svc
    namespace: longhorn-system
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
    syncOptions:
      - CreateNamespace=true
```

### Using Manifests Instead

```bash
# Add Kubernetes manifests directly
cd 01-longhorn/
kubectl create -f longhorn-install.yaml --dry-run=client -o yaml > manifest.yaml

# Commit and push
git add .
git commit -m "Add Longhorn manifests"
git push
```

ArgoCD will sync automatically and deploy in wave order.

## Sync Wave Guidelines

- **Wave 0:** Namespaces, CRDs, basic resources
- **Wave 1:** Storage (needed by other components)
- **Wave 2:** Networking (needs storage for configs)
- **Wave 3:** Advanced features (needs storage + networking)

## Verification

```bash
# Check deployment order
kubectl get applications -n argocd

# Watch infrastructure deployment
kubectl get application infrastructure -n argocd -w

# Check health
kubectl describe application infrastructure -n argocd
```

## Dependencies

Infrastructure must be healthy before apps deploy (managed via sync wave 10).
