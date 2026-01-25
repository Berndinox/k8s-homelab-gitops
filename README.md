# Kubernetes Cluster GitOps

GitOps repository for RKE2 Kubernetes cluster with:
- **Cilium CNI** with BGP & Hubble (replacing Canal)
- **Longhorn** distributed storage
- **Multus** for multi-NIC support (VLANs)
- **KubeVirt** for VM workloads

## Architecture

```
3x Ubuntu 24.04 Hosts (host01, host02, host03)
├── Management Network: VLAN 200 (eno1)
├── Cluster Network: VLAN 100 (bond0) - LACP 20Gbit
└── Application VLANs: 5, 10, 30, 40, 50, 60, 100, 200
```

## Repository Structure

```
├── bootstrap/          # ArgoCD bootstrap
├── argocd-apps/       # App-of-Apps definitions
├── infrastructure/    # Platform components (ordered)
│   ├── 00-namespaces/
│   ├── 01-cilium/     # CNI (replaces Canal)
│   ├── 02-longhorn/   # Storage
│   ├── 03-multus/     # Multi-NIC
│   └── 04-kubevirt/   # VM Runtime
└── applications/      # User workloads
    └── test-vm/       # Test VM with multi-VLAN
```

## Getting Started

### 1. Bootstrap ArgoCD
```bash
kubectl apply -f bootstrap/root-app.yaml
```

### 2. Watch deployment
```bash
# All applications
kubectl get applications -n argocd -w

# Infrastructure pods
kubectl get pods -A
```

### 3. Access ArgoCD UI
```bash
kubectl port-forward svc/argocd-server -n argocd 8080:443 --address=0.0.0.0
```
- URL: https://10.0.200.103:8080
- User: admin
- Pass: `kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d`

## Deployment Order

1. ✅ Namespaces
2. ✅ Cilium (CNI) - Canal wird ersetzt
3. ✅ Longhorn (Storage)
4. ✅ Multus (Multi-NIC) + VLAN NetworkAttachmentDefinitions
5. ✅ KubeVirt (VM Runtime)

## Notes

- **Cilium BGP**: Configured for L4 LoadBalancer announcements
- **Hubble**: Network observability enabled
- **VLANs**: All 8 VLANs available via Multus
- **Storage**: Longhorn uses Cluster Network (VLAN 100) for replication

## Troubleshooting

```bash
# Check ArgoCD app status
kubectl get app -n argocd

# Check specific app
kubectl describe app cilium -n argocd

# Force sync
kubectl patch app cilium -n argocd -p '{"operation":{"initiatedBy":{"username":"admin"},"sync":{"revision":"HEAD"}}}' --type merge
```