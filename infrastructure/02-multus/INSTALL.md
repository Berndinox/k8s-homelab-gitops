# Multus CNI Installation

Multus muss **vor** den NetworkAttachmentDefinitions installiert werden.

## Quick Install

```bash
# 1. Multus CNI DaemonSet installieren
kubectl apply -f https://raw.githubusercontent.com/k8snetworkplumbingwg/multus-cni/master/deployments/multus-daemonset-thick.yml

# 2. Whereabouts IPAM installieren
kubectl apply -f https://raw.githubusercontent.com/k8snetworkplumbingwg/whereabouts/master/doc/crds/daemonset-install.yaml
kubectl apply -f https://raw.githubusercontent.com/k8snetworkplumbingwg/whereabouts/master/doc/crds/whereabouts.cni.cncf.io_ippools.yaml
kubectl apply -f https://raw.githubusercontent.com/k8snetworkplumbingwg/whereabouts/master/doc/crds/whereabouts.cni.cncf.io_overlappingrangeipreservations.yaml

# 3. Warten bis Multus Pods ready
kubectl wait --for=condition=ready pod -l app=multus -n kube-system --timeout=300s

# 4. NetworkAttachmentDefinitions via ArgoCD deployen
kubectl apply -f network-attachment-definitions.yaml
```

## Verification

```bash
# Multus Pods prüfen
kubectl get pods -n kube-system -l app=multus

# CRDs prüfen
kubectl get crd | grep -E "network-attachment|whereabouts"

# NetworkAttachmentDefinitions prüfen
kubectl get network-attachment-definitions -A

# Test Pod mit Multus
kubectl run test-multus --image=nicolaka/netshoot --annotations="k8s.v1.cni.cncf.io/networks=vlan10-dmz" -- sleep infinity
kubectl exec -it test-multus -- ip addr show
kubectl delete pod test-multus
```

## Manual Installation (Alternative)

Falls die Quick Install nicht funktioniert, siehe [README.md](README.md) für Details zur manuellen Installation.

## Talos-spezifische Anpassungen

Keine! Talos hat bereits:
- ✅ bond0 als parent interface verfügbar
- ✅ Alle benötigten Kernel-Module (bridge, veth, macvlan, ipvlan)
- ✅ CNI Plugin-Verzeichnis (/opt/cni/bin)

Multus wird automatisch das richtige interface (bond0) finden und nutzen.

## Nach Installation

Die NetworkAttachmentDefinitions werden via ArgoCD Sync Wave 2 automatisch deployed, sobald Multus läuft.

Prüfe den Status:
```bash
kubectl get applications -n argocd | grep multus
kubectl get network-attachment-definitions -A
```
