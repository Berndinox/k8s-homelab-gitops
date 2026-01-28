# Infrastructure Components

This directory contains core infrastructure components deployed in sequence using ArgoCD sync waves.

## Deployment Order (Sync Waves)

Components are deployed in numbered order. Each must be healthy before the next begins.

```
Wave -5: 00-cilium/        → CNI (Network) - MUST be first!
Wave  1: 01-longhorn/      → Persistent storage
Wave  2: 02-multus/        → Multi-NIC networking
Wave  3: 03-kubevirt/      → VM virtualization
```


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
