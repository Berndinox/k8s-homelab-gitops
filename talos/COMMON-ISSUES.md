# Common Issues & Solutions

Häufige Probleme bei Talos + Cilium + KubeVirt + Longhorn + Multus und deren Lösungen.

## Talos Installation

### Issue: Node nicht erreichbar nach Installation

**Symptome:**
- `talosctl` kann nicht zu Node verbinden
- Timeout bei API-Anfragen

**Ursachen & Lösungen:**

1. **Falsche IP-Adresse:**
   ```bash
   # Prüfen auf Management Interface (eno1)
   # Node bootet mit DHCP, nicht mit statischer VLAN IP!
   talosctl --insecure --nodes <DHCP-IP> get links
   ```

2. **Netzwerk nicht konfiguriert:**
   ```bash
   # Check network status
   talosctl --insecure --nodes <IP> get networkstatus
   ```

3. **Bond oder VLAN fehlgeschlagen:**
   - Interface-Namen stimmen nicht (enp1s0 vs eth0)
   - LACP nicht aktiviert auf Switch
   - VLAN 100 nicht auf Switch konfiguriert

**Lösung:**
```bash
# 1. Über Management-Interface verbinden
talosctl --insecure --nodes <MGMT-IP> get links

# 2. Interface-Namen prüfen
# 3. Config anpassen
# 4. Neu apply
talosctl apply-config --insecure --nodes <MGMT-IP> --file configs/host03.yaml
```

**Quellen:**
- [Can't get network running in Talos](https://github.com/siderolabs/talos/discussions/8077)
- [Unable to get VLAN working](https://github.com/siderolabs/talos/discussions/8676)

---

### Issue: Disk nicht gefunden bei Installation

**Symptome:**
- Installation schlägt fehl mit "no disks found"
- diskSelector matcht keine Disk

**Ursache:**
- diskSelector Kriterien zu strikt
- Disk-Größe oder Typ stimmt nicht überein

**Lösung:**
```bash
# 1. Disks prüfen nach USB Boot
talosctl --insecure --nodes <IP> disks

# 2. Disk IDs anzeigen
talosctl --insecure --nodes <IP> ls /dev/disk/by-id/

# 3. In config exakte Disk angeben statt diskSelector:
machine:
  install:
    disk: /dev/nvme0n1  # Exakte Disk
    # ODER:
    diskSelector:
      size: "<= 644245094400"  # 600GB in BYTES
      type: nvme
```

**Wichtig:** Disk-Größen müssen in **Bytes** angegeben werden, nicht als String wie "< 1TB"!

---

## Cilium CNI

### Issue: Cilium Pods starten nicht / CrashLoopBackOff

**Symptome:**
```
cilium-xxxxx   0/1   CrashLoopBackOff
```

**Ursachen & Lösungen:**

1. **kube-proxy nicht deaktiviert:**
   ```yaml
   # In machine config:
   cluster:
     proxy:
       disabled: true  # MUSS auf true!
   ```

2. **Kernel Module fehlen:**
   ```bash
   # Check ob Module geladen
   talosctl read /proc/modules --nodes <IP> | grep -E "br_netfilter|xt_conntrack"

   # In machine config prüfen:
   machine:
     kernel:
       modules:
         - name: br_netfilter
         - name: xt_conntrack
   ```

3. **VIP nicht erreichbar:**
   ```yaml
   # Cilium Helm values:
   k8sServiceHost: 10.0.100.111  # VIP korrekt?
   k8sServicePort: 6443
   ```

**Lösung:**
```bash
# Cilium Logs prüfen
kubectl logs -n kube-system ds/cilium -f

# Cilium neu deployen
helm upgrade cilium cilium/cilium --namespace kube-system --reuse-values
```

**Quellen:**
- [Panic on Talos caused by Cilium EBPF](https://github.com/cilium/cilium/issues/34700)
- [Talos HA Installation not working with cilium](https://github.com/siderolabs/talos/issues/9128)

---

### Issue: VLAN Traffic Drop / Connectivity Failures

**Symptome:**
- Cilium connectivity test fails
- "VLAN traffic disallowed by VLAN filter" errors
- Pods können nicht miteinander kommunizieren über VLANs

**Ursache:**
- Cilium Host Firewall blockiert VLAN Traffic
- Bridge Interface forwarded VLAN packets falsch

**Lösung:**
```yaml
# Option 1: Host Firewall deaktivieren (nur für Testing!)
hostFirewall:
  enabled: false

# Option 2: Firewall Regeln anpassen
# Cilium NetworkPolicy für VLAN traffic erstellen
```

**Workaround:**
```bash
# Temporär für Testing
kubectl exec -n kube-system ds/cilium -- cilium config HostFirewall=false
```

**Quellen:**
- [Connectivity test fails due to VLAN packet drops](https://github.com/cilium/cilium/issues/36830)
- [Cilium hostFirewall rules are ignored in tagged VLAN](https://github.com/cilium/cilium/issues/40247)

---

### Issue: Cilium hostPort nicht funktionierend

**Symptome:**
- KubeVirt VMs nicht erreichbar über hostPort
- LoadBalancer IPs nicht assigned

**Ursache:**
- hostPort feature nicht aktiviert
- LoadBalancer mode falsch

**Lösung:**
```yaml
# Cilium Helm values:
hostPort:
  enabled: true  # Für KubeVirt VMs!

loadBalancer:
  mode: hybrid
  acceleration: native
```

---

## Longhorn Storage

### Issue: Longhorn Pods starten nicht

**Symptome:**
```
longhorn-manager-xxxxx   0/1   Error
```

**Ursachen & Lösungen:**

1. **System Extensions fehlen:**
   ```yaml
   # In machine config:
   machine:
     install:
       extensions:
         - image: ghcr.io/siderolabs/iscsi-tools:v0.1.4
         - image: ghcr.io/siderolabs/util-linux-tools:v0.1.0
   ```

2. **Kernel Modules fehlen:**
   ```yaml
   machine:
     kernel:
       modules:
         - name: iscsi_tcp
         - name: nbd  # Für Longhorn!
   ```

3. **Pod Security Policy zu strikt:**
   ```bash
   # Namespace labeln
   kubectl label namespace longhorn-system \
     pod-security.kubernetes.io/enforce=privileged \
     pod-security.kubernetes.io/audit=privileged \
     pod-security.kubernetes.io/warn=privileged
   ```

4. **Kubelet Path fehlt:**
   ```yaml
   # In machine config:
   machine:
     kubelet:
       extraMounts:
         - destination: /var/lib/longhorn
           type: bind
           source: /var/lib/longhorn
           options:
             - bind
             - rshared
             - rw
   ```

**Lösung:**
```bash
# 1. Extensions + Modules in machine config hinzufügen
# 2. Config neu applyen
talosctl apply-config --nodes <IP> --file configs/<host>.yaml

# 3. Namespace labeln (siehe oben)

# 4. Longhorn neu deployen
kubectl apply -f infrastructure/01-longhorn/
```

**Quellen:**
- [Installing Longhorn on Talos Linux](https://phin3has.blog/posts/talos-longhorn/)
- [Longhorn Talos Linux Support](https://longhorn.io/docs/1.10.1/advanced-resources/os-distro-specific/talos-linux-support/)
- [Install Longhorn on Talos](https://hackmd.io/@QI-AN/Install-Longhorn-on-Talos-Kubernetes)

---

### Issue: Longhorn Volumes bleiben Pending

**Symptome:**
- PVCs stuck in "Pending"
- "no nodes available for scheduling"

**Ursache:**
- Disks nicht korrekt konfiguriert
- Zu wenig Speicherplatz
- Node-Selector passt nicht

**Lösung:**
```bash
# 1. Longhorn Nodes prüfen
kubectl get nodes -n longhorn-system -o wide

# 2. Disk Status prüfen (Longhorn UI oder CLI)
kubectl get lhn -n longhorn-system  # Longhorn Nodes

# 3. Verfügbaren Speicher prüfen
# Longhorn UI → Node → Disk
# Sollte die größere NVMe (2TB+) zeigen

# 4. Falls Disk fehlt: Manuell hinzufügen
# Longhorn UI → Node → Edit Node → Add Disk
# Path: /var/lib/longhorn (automatisch von Talos gemountet)
```

---

### Issue: Data Loss bei Node Upgrade

**Symptome:**
- Nach `talosctl upgrade` sind Longhorn Replicas weg
- Volumes nicht mehr verfügbar

**Ursache:**
- Talos wipet `/var/lib/longhorn` bei Upgrade ohne `--preserve`

**Lösung:**
```bash
# IMMER mit --preserve upgraden!
talosctl upgrade \
  --nodes <IP> \
  --image ghcr.io/siderolabs/installer:v1.9.4 \
  --preserve

# Seit Talos 1.8+ ist --preserve automatisch default
```

**Quelle:**
- [Talos path confusion /var/lib/longhorn](https://github.com/longhorn/longhorn/issues/8227)

---

## KubeVirt Virtualization

### Issue: KubeVirt Pods starten nicht

**Symptome:**
```
virt-handler-xxxxx   0/1   Error
```

**Ursachen & Lösungen:**

1. **Hardware Virtualization nicht aktiviert:**
   ```bash
   # BIOS Check erforderlich!
   # Intel: VT-x aktivieren
   # AMD: AMD-V aktivieren

   # Auf Node prüfen:
   talosctl read /proc/cpuinfo --nodes <IP> | grep -E "vmx|svm"
   # Intel CPUs: Sollte "vmx" zeigen
   # AMD CPUs: Sollte "svm" zeigen

   # Intel VT-x Modul prüfen:
   talosctl read /proc/modules --nodes <IP> | grep kvm_intel
   # Sollte: kvm_intel ... (loaded)
   ```

2. **Kernel Modules fehlen:**
   ```yaml
   machine:
     kernel:
       modules:
         - name: kvm          # Hardware virtualization
         - name: kvm_intel    # Intel VT-x (oder kvm_amd für AMD)
         - name: vhost_net    # Für VMs!
         - name: vhost_vsock
         - name: tun
   ```

   **Check ob Module geladen:**
   ```bash
   talosctl read /proc/modules --nodes <IP> | grep -E "kvm|vhost|tun"
   ```

3. **Privileged Pods nicht erlaubt:**
   ```bash
   # Namespace labeln
   kubectl label namespace kubevirt \
     pod-security.kubernetes.io/enforce=privileged
   ```

**Quelle:**
- [Install KubeVirt on Talos](https://www.talos.dev/v1.11/advanced/install-kubevirt/)

---

### Issue: VM kann nicht starten / DataVolume Import fails

**Symptome:**
- VM stuck in "Provisioning"
- CDI Import Pod fails

**Ursache:**
- Kein Storage verfügbar
- local-path-provisioner fehlt (für CDI scratch space)

**Lösung:**
```bash
# 1. Prüfen ob StorageClass vorhanden
kubectl get sc

# 2. Falls CDI scratch space fehlt:
# local-path-provisioner installieren ODER
# Longhorn als default StorageClass nutzen

# 3. VM neu starten
kubectl delete vm <vm-name>
kubectl apply -f vm.yaml
```

---

## Multus CNI

### Issue: Multus NetworkAttachmentDefinition nicht verfügbar

**Symptome:**
- `kubectl get net-attach-def` → not found
- Pods können keine secondary interfaces attachen

**Ursache:**
- Multus CRDs nicht installiert
- Multus DaemonSet nicht running

**Lösung:**
```bash
# 1. Multus CRDs prüfen
kubectl get crd | grep k8s.cni.cncf.io

# 2. Multus Pods prüfen
kubectl get pods -n kube-system -l app=multus

# 3. Falls fehlt: Multus via ArgoCD neu deployen
kubectl apply -f infrastructure/02-multus/
```

---

## Node Join Probleme

### Issue: Worker Node joint nicht

**Symptome:**
- Node erscheint in `talosctl get members` aber nicht in `kubectl get nodes`
- Kubelet startet nicht

**Ursachen & Lösungen:**

1. **Cilium nicht ready auf Controlplane:**
   ```bash
   # Auf Controlplane prüfen:
   kubectl get pods -n kube-system -l k8s-app=cilium
   # MUSS "Running" und "1/1 Ready" sein
   ```

2. **VIP nicht erreichbar:**
   ```bash
   # Auf Worker prüfen (via talosctl):
   talosctl --nodes <WORKER-IP> exec -- ping -c 4 10.0.100.111
   ```

3. **Kubelet Config falsch:**
   ```bash
   # Kubelet logs prüfen
   talosctl logs kubelet --nodes <WORKER-IP>
   ```

**Lösung:**
```bash
# 1. Cilium status auf Controlplane prüfen
kubectl exec -n kube-system ds/cilium -- cilium status

# 2. Netzwerk-Connectivity testen
talosctl --nodes <WORKER-IP> exec -- ping -c 4 10.0.100.103

# 3. Worker config neu applyen
talosctl apply-config --nodes <WORKER-IP> --file configs/<host>.yaml
```

---

## ArgoCD Problems

### Issue: ArgoCD Applications stuck in "OutOfSync"

**Symptome:**
- Application zeigt "OutOfSync" trotz korrektem Git content
- Sync schlägt fehl

**Ursachen & Lösungen:**

1. **CRDs fehlen:**
   ```bash
   # Gateway API CRDs für Cilium fehlen?
   kubectl get crd | grep gateway.networking.k8s.io

   # Falls fehlt:
   kubectl apply -f infrastructure/00-cilium/gateway-api-crds.yaml
   ```

2. **Sync Wave Order:**
   ```bash
   # Apps syncen in falscher Reihenfolge
   # Prüfen: Sync Wave annotations
   kubectl get application -n argocd -o yaml | grep sync-wave

   # Expected:
   # -5: Cilium (already running)
   #  0: Namespaces
   #  1: Longhorn
   #  2: Multus
   #  3: KubeVirt
   ```

3. **Cilium adoption fails:**
   ```bash
   # Cilium wurde via Helm installiert, ArgoCD will neu deployen
   # Check ignoreDifferences in cilium-helm.yaml

   # Force adopt:
   kubectl annotate helmrelease cilium -n kube-system \
     meta.helm.sh/release-name=cilium \
     meta.helm.sh/release-namespace=kube-system
   ```

**Lösung:**
```bash
# Manual sync mit force
kubectl -n argocd patch app <app-name> \
  -p '{"spec":{"syncPolicy":{"syncOptions":["Force=true"]}}}' \
  --type merge

# Oder via ArgoCD CLI
argocd app sync <app-name> --force
```

---

## Performance Issues

### Issue: Cilium hohe CPU Last

**Symptome:**
- Cilium Pods verbrauchen viel CPU
- eBPF compile-Zeit hoch

**Ursache:**
- Zu viele Flows in Hubble
- eBPF JIT nicht aktiviert

**Lösung:**
```yaml
# Cilium Helm values:
hubble:
  metrics:
    enabled:
      - dns:query  # Nur notwendige Metrics
      - drop
      # http/tcp/flow disabled für weniger Load

# eBPF JIT prüfen:
# sysctl: net.core.bpf_jit_enable = 1 (bereits in base-patch.yaml)
```

---

## Debugging Cheatsheet

```bash
# Talos Logs
talosctl logs --nodes <IP>
talosctl logs kubelet --nodes <IP>
talosctl logs etcd --nodes <IP>

# Kernel Logs
talosctl dmesg --nodes <IP> -f

# Netzwerk Status
talosctl get links --nodes <IP>
talosctl get addresses --nodes <IP>
talosctl get routes --nodes <IP>

# Cilium Status
kubectl exec -n kube-system ds/cilium -- cilium status
kubectl exec -n kube-system ds/cilium -- cilium endpoint list

# Longhorn Status
kubectl get lhn -n longhorn-system  # Longhorn Nodes
kubectl get lvr -n longhorn-system  # Longhorn Volume Replicas

# KubeVirt Status
kubectl get vmi  # Running VMs
kubectl get vms  # VM definitions

# Multus Status
kubectl get net-attach-def -A
```

---

## Weitere Ressourcen

**Talos Dokumentation:**
- [Talos Linux Docs](https://www.talos.dev)
- [Talos Troubleshooting](https://www.talos.dev/latest/learn-more/troubleshooting/)

**Community:**
- [Talos GitHub Discussions](https://github.com/siderolabs/talos/discussions)
- [Talos Slack](https://slack.dev.talos-systems.io/)
- [Cilium Slack](https://cilium.io/slack)

**Tutorials:**
- [Installing Cilium and Multus on Talos OS](https://www.itguyjournals.com/installing-cilium-and-multus-on-talos-os-for-advanced-kubernetes-networking/)
- [Installing Longhorn on Talos With Helm](https://joshrnoll.com/installing-longhorn-on-talos-with-helm/)

**GitHub Issues:**
- [Talos Issues](https://github.com/siderolabs/talos/issues)
- [Cilium Issues](https://github.com/cilium/cilium/issues)
- [Longhorn Issues](https://github.com/longhorn/longhorn/issues)
