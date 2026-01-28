# Talos Bootstrap Flow

Visuelle Darstellung des Bootstrap-Prozesses für das Talos Homelab Cluster.

## Übersicht

```
USB Boot → Talos Installation → K8s Bootstrap → Cilium (Helm) → ArgoCD → GitOps Infrastructure
```

## Detaillierter Ablauf

### Phase 1: OS Installation (5-10 min)

```
┌─────────────────────────────────────────┐
│  1. USB Boot (Talos Live Environment)  │
│     - Talos läuft komplett in RAM      │
│     - Disk noch unberührt               │
└─────────────────────────────────────────┘
                  ↓
┌─────────────────────────────────────────┐
│  2. Apply Machine Config                │
│     talosctl apply-config --insecure    │
│     --nodes 10.0.100.103                │
│     --file configs/host03.yaml          │
└─────────────────────────────────────────┘
                  ↓
┌─────────────────────────────────────────┐
│  3. Talos Installation auf Disk         │
│     - Kleinere NVMe (<1TB) erkannt      │
│     - Partitionierung:                  │
│       • EFI (100MB)                     │
│       • Boot A (1GB)                    │
│       • Boot B (1GB)                    │
│       • State (100MB)                   │
│       • Ephemeral (Rest)                │
│     - Optional: LUKS Encryption         │
└─────────────────────────────────────────┘
                  ↓
┌─────────────────────────────────────────┐
│  4. Reboot von Disk                     │
│     - Netzwerk: Bond0 + VLAN 100        │
│     - IP: 10.0.100.103/24               │
│     - Talos API bereit                  │
└─────────────────────────────────────────┘
```

**Zeit:** ~5-10 Minuten
**Output:** Talos OS läuft, keine Kubernetes Komponenten

---

### Phase 2: Kubernetes Bootstrap (5-10 min)

```
┌─────────────────────────────────────────┐
│  5. Bootstrap Kubernetes                │
│     talosctl bootstrap                  │
│     --nodes 10.0.100.103                │
└─────────────────────────────────────────┘
                  ↓
┌─────────────────────────────────────────┐
│  6. Talos deployt K8s Control Plane     │
│     - etcd                              │
│     - kube-apiserver                    │
│     - kube-controller-manager           │
│     - kube-scheduler                    │
│     - kubelet                           │
└─────────────────────────────────────────┘
                  ↓
┌─────────────────────────────────────────┐
│  7. K8s API Server erreichbar           │
│     https://10.0.100.111:6443           │
│     (VIP via Talos KubePrism)           │
└─────────────────────────────────────────┘
                  ↓
┌─────────────────────────────────────────┐
│  8. Kubeconfig holen                    │
│     talosctl kubeconfig                 │
│     kubectl get nodes                   │
│     → Node status: NotReady (kein CNI!) │
└─────────────────────────────────────────┘
```

**Zeit:** ~5-10 Minuten
**Output:** Kubernetes läuft, aber Pods können nicht starten (kein Networking)

---

### Phase 3: Cilium Installation (2-5 min)

```
┌─────────────────────────────────────────┐
│  9. Install Cilium via Helm             │
│     ./scripts/install-cilium.sh         │
└─────────────────────────────────────────┘
                  ↓
┌─────────────────────────────────────────┐
│  10. Helm deployt Cilium                │
│      - DaemonSet auf allen Nodes        │
│      - Operator Deployment              │
│      - Hubble Relay/UI                  │
└─────────────────────────────────────────┘
                  ↓
┌─────────────────────────────────────────┐
│  11. Cilium Pods starten                │
│      - CNI Plugin aktiv                 │
│      - eBPF Programme laden             │
│      - kube-proxy Replacement aktiv     │
└─────────────────────────────────────────┘
                  ↓
┌─────────────────────────────────────────┐
│  12. Node Ready!                        │
│      kubectl get nodes                  │
│      → Node status: Ready               │
└─────────────────────────────────────────┘
```

**Zeit:** ~2-5 Minuten
**Output:** Cluster funktionsfähig, Pods können deployed werden

**WICHTIG:** Cilium MUSS vor ArgoCD installiert werden!
- ArgoCD läuft als Pods
- Pods brauchen CNI für Networking
- Ohne Cilium → keine Pods → kein ArgoCD → Deadlock!

---

### Phase 4: GitOps Bootstrap (3-10 min)

```
┌─────────────────────────────────────────┐
│  13. Bootstrap ArgoCD                   │
│      ./scripts/bootstrap-gitops.sh      │
└─────────────────────────────────────────┘
                  ↓
┌─────────────────────────────────────────┐
│  14. ArgoCD Installation                │
│      - Namespace: argocd                │
│      - Controller, Server, Repo-Server  │
│      - ApplicationSet Controller        │
└─────────────────────────────────────────┘
                  ↓
┌─────────────────────────────────────────┐
│  15. ArgoCD adoptiert Cilium            │
│      kubectl apply -f                   │
│        infrastructure/00-cilium/        │
│      → Cilium wird nicht neu deployed   │
│      → ArgoCD übernimmt Management      │
└─────────────────────────────────────────┘
                  ↓
┌─────────────────────────────────────────┐
│  16. Root App erstellen                 │
│      bootstrap/root-app.yaml            │
│      → Verweist auf argocd-apps/        │
└─────────────────────────────────────────┘
                  ↓
┌─────────────────────────────────────────┐
│  17. Infrastructure App Sync            │
│      Wave -5: Cilium (adopted)          │
│      Wave 0:  Namespaces                │
│      Wave 1:  Longhorn                  │
│      Wave 2:  Multus                    │
│      Wave 3:  KubeVirt                  │
└─────────────────────────────────────────┘
                  ↓
┌─────────────────────────────────────────┐
│  18. Apps Deployment                    │
│      Wave 10: Application Workloads     │
└─────────────────────────────────────────┘
```

**Zeit:** ~3-10 Minuten (abhängig von Image Pull)
**Output:** Vollständiges GitOps-managed Cluster

---

### Phase 5: Worker Nodes Join (2-5 min/node)

```
┌─────────────────────────────────────────┐
│  19. Host01 & Host02 Installation       │
│      - USB Boot                         │
│      - Apply Worker Config              │
│      - Talos Installation               │
│      - Reboot                           │
└─────────────────────────────────────────┘
                  ↓
┌─────────────────────────────────────────┐
│  20. Auto-Join zum Cluster              │
│      - Verbindung zu VIP                │
│      - Zertifikat-Austausch             │
│      - Kubelet registriert              │
└─────────────────────────────────────────┘
                  ↓
┌─────────────────────────────────────────┐
│  21. Cilium auf Workers                 │
│      - DaemonSet deployed automatisch   │
│      - BGP Peering (falls aktiviert)    │
│      - Node wird Ready                  │
└─────────────────────────────────────────┘
```

**Zeit:** ~2-5 Minuten pro Node
**Output:** 3-Node HA Cluster

---

## Gesamtzeit

| Phase | Dauer | Kumulativ |
|-------|-------|-----------|
| OS Installation | 5-10 min | 5-10 min |
| K8s Bootstrap | 5-10 min | 10-20 min |
| Cilium Install | 2-5 min | 12-25 min |
| GitOps Bootstrap | 3-10 min | 15-35 min |
| Worker Join (x2) | 4-10 min | 19-45 min |

**Total:** 20-45 Minuten für vollständiges 3-Node Cluster

---

## Dependency Graph

```
Talos OS
    ↓
Kubernetes API Server
    ↓
Cilium CNI ────────┐
    ↓              │
ArgoCD ←───────────┘ (adoptiert Cilium)
    ↓
GitOps Infrastructure
    ├── Longhorn (Storage)
    ├── Multus (Networking)
    └── KubeVirt (VMs)
    ↓
Application Workloads
```

---

## Kritische Reihenfolge

### ✅ RICHTIG: Cilium vor ArgoCD

```
1. Talos Installation
2. K8s Bootstrap
3. Cilium via Helm  ← ERST
4. ArgoCD          ← DANN
5. GitOps Apps
```

**Warum?** ArgoCD läuft als Pods, Pods brauchen CNI.

### ❌ FALSCH: ArgoCD vor Cilium

```
1. Talos Installation
2. K8s Bootstrap
3. ArgoCD          ← DEADLOCK!
   └→ Pods können nicht starten (kein CNI)
   └→ Keine ArgoCD-Controller
   └→ Cilium wird nie deployed
```

---

## Troubleshooting Bootstrap

### Node bleibt NotReady

**Problem:** Node zeigt NotReady nach K8s Bootstrap

**Ursache:** Cilium nicht installiert

**Lösung:**
```bash
# Check ob Cilium läuft
kubectl get pods -n kube-system -l k8s-app=cilium

# Falls nicht vorhanden:
./scripts/install-cilium.sh
```

### ArgoCD Pods starten nicht

**Problem:** ArgoCD Pods stuck in ContainerCreating

**Ursache:** Cilium nicht ready

**Lösung:**
```bash
# Check Cilium Status
kubectl exec -n kube-system ds/cilium -- cilium status

# Cilium logs prüfen
kubectl logs -n kube-system -l k8s-app=cilium
```

### Infrastructure Apps syncen nicht

**Problem:** ArgoCD zeigt "OutOfSync" für Infrastructure

**Ursache:** Meist Timing-Problem oder fehlende CRDs

**Lösung:**
```bash
# Manuelles Sync erzwingen
kubectl -n argocd get applications
kubectl -n argocd patch app infrastructure -p '{"operation":{"sync":{"syncStrategy":{"hook":{}}}}}' --type merge

# Oder via ArgoCD CLI
argocd app sync infrastructure
```

---

## Post-Bootstrap Verification

Nach erfolgreichem Bootstrap sollte folgendes funktionieren:

```bash
# 1. Alle Nodes Ready
kubectl get nodes
# EXPECTED: All nodes STATUS=Ready

# 2. Cilium Healthy
kubectl exec -n kube-system ds/cilium -- cilium status
# EXPECTED: All checks OK

# 3. ArgoCD Apps Synced
kubectl get applications -n argocd
# EXPECTED: All apps HEALTH=Healthy, SYNC=Synced

# 4. Infrastructure Components
kubectl get pods -n longhorn-system   # Longhorn
kubectl get pods -n kubevirt           # KubeVirt
kubectl get crd | grep multus          # Multus

# 5. Connectivity Test
kubectl run test --image=nginx --rm -it -- /bin/sh
# Should be able to pull image and start
```

---

## Best Practices

1. **Immer gleiche Reihenfolge einhalten**
   - OS → K8s → Cilium → ArgoCD → Apps

2. **Warten auf Readiness**
   - Nach jedem Schritt warten bis Status "Ready"
   - Nicht weitermachen wenn Fehler auftreten

3. **Logs bei Problemen**
   - Talos: `talosctl logs kubelet`
   - Cilium: `kubectl logs -n kube-system ds/cilium`
   - ArgoCD: `kubectl logs -n argocd deployment/argocd-application-controller`

4. **Backups vor Änderungen**
   - etcd Snapshot: `talosctl etcd snapshot`
   - Configs in Git committen

5. **Dokumentation aktuell halten**
   - Änderungen in README.md dokumentieren
   - Custom Patches in separate Files

---

## Vergleich: RKE2 vs Talos Bootstrap

| Aspekt | RKE2 (CoreOS) | Talos |
|--------|---------------|-------|
| **CNI Installation** | Via RKE2 (automatisch) | Manuell vor ArgoCD |
| **Bootstrap-Tool** | rke2-server.service | talosctl bootstrap |
| **Config-Format** | Butane/Ignition | Machine Config YAML |
| **CNI-Timing** | Während K8s Start | Nach K8s Start |
| **ArgoCD Deploy** | Via systemd oneshot | Via kubectl/Helm |
| **Chicken-Egg** | Kein Problem | Muss gelöst werden |

**Talos Vorteil:** Klare Trennung, bessere Kontrolle
**Talos Nachteil:** Mehr manuelle Schritte

---

## Weiterführende Infos

- [Talos Bootstrap Docs](https://www.talos.dev/latest/introduction/getting-started/)
- [Cilium Installation Docs](https://docs.cilium.io/en/stable/installation/)
- [ArgoCD Bootstrap Docs](https://argo-cd.readthedocs.io/en/stable/getting_started/)
