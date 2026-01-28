# Multus CNI Configuration

Multus CNI ermöglicht mehrere Netzwerk-Interfaces für Pods und VMs.

## Konfigurierte VLANs

Alle VLANs nutzen das **bond0 trunk interface** und **macvlan mode**.

| VLAN ID | Name | Subnet | Gateway | Zweck |
|---------|------|--------|---------|-------|
| 5 | vlan5-wan | 10.0.5.0/24 | 10.0.5.1 | WAN (External) |
| 10 | vlan10-dmz | 10.0.10.0/24 | 10.0.10.1 | DMZ/Public Services |
| 30 | vlan30-wifi | 10.0.30.0/24 | 10.0.30.1 | WIFI Network |
| 40 | vlan40-client | 10.0.40.0/24 | 10.0.40.1 | Client Network |
| 50 | vlan50-server | 10.0.50.0/24 | 10.0.50.1 | Server Network |
| 60 | vlan60-wifi-secure | 10.0.60.0/24 | 10.0.60.1 | WiFi Secure |
| 100 | vlan100-cluster | 10.0.100.0/24 | 10.0.100.1 | Cluster (Nodes) |
| 200 | vlan200-management | 10.0.200.0/24 | 10.0.200.1 | Management |

⚠️ **WICHTIG:** Passe die IP-Ranges in `network-attachment-definitions.yaml` an deine tatsächlichen Subnetze an!

## IPAM: Whereabouts

Alle NetworkAttachmentDefinitions nutzen **Whereabouts IPAM** für automatische IP-Vergabe:
- IP-Pool pro VLAN konfigurierbar
- Automatische IP-Vergabe an Pods/VMs
- Collision-frei über alle Nodes

### VLAN 100 Besonderheit

VLAN 100 wird von den Nodes selbst genutzt. Die IPAM-Konfiguration:
- `range_start: 10.0.100.150` - Pods bekommen IPs ab .150
- `range_end: 10.0.100.254` - Bis .254
- `exclude:` Node-IPs (.101, .102, .103) und VIP (.111) ausgeschlossen

## Nutzung in Pods

### Standard Pod (nur Cilium)
```yaml
apiVersion: v1
kind: Pod
metadata:
  name: my-pod
spec:
  containers:
  - name: app
    image: nginx
# Nur Cilium CNI (Pod Network 10.1.x.x)
```

### Pod mit zusätzlichem VLAN-Interface
```yaml
apiVersion: v1
kind: Pod
metadata:
  name: my-multi-nic-pod
  annotations:
    k8s.v1.cni.cncf.io/networks: vlan10-dmz
spec:
  containers:
  - name: app
    image: nginx
# eth0: Cilium (10.1.x.x)
# net1: VLAN 10 (10.0.10.x)
```

### Pod mit mehreren VLAN-Interfaces
```yaml
apiVersion: v1
kind: Pod
metadata:
  name: firewall-pod
  annotations:
    k8s.v1.cni.cncf.io/networks: |
      [
        {"name": "vlan10-dmz"},
        {"name": "vlan30-guest"},
        {"name": "vlan100-cluster"}
      ]
spec:
  containers:
  - name: opnsense
    image: opnsense:latest
# eth0: Cilium (10.1.x.x)
# net1: VLAN 10 (10.0.10.x) - DMZ
# net2: VLAN 30 (10.0.30.x) - Guest
# net3: VLAN 100 (10.0.100.x) - Internal
```

### Pod mit statischer IP
```yaml
apiVersion: v1
kind: Pod
metadata:
  name: static-ip-pod
  annotations:
    k8s.v1.cni.cncf.io/networks: |
      [
        {
          "name": "vlan10-dmz",
          "ips": ["10.0.10.100"]
        }
      ]
spec:
  containers:
  - name: app
    image: nginx
```

## Nutzung in KubeVirt VMs

### VM mit VLAN-Interface
```yaml
apiVersion: kubevirt.io/v1
kind: VirtualMachine
metadata:
  name: opnsense-firewall
spec:
  template:
    metadata:
      annotations:
        k8s.v1.cni.cncf.io/networks: |
          [
            {"name": "vlan10-dmz", "interface": "wan"},
            {"name": "vlan30-guest", "interface": "lan1"},
            {"name": "vlan40-iot", "interface": "lan2"}
          ]
    spec:
      domain:
        devices:
          interfaces:
          - name: default
            bridge: {}
          - name: wan
            bridge: {}
          - name: lan1
            bridge: {}
          - name: lan2
            bridge: {}
        resources:
          requests:
            memory: 4Gi
            cpu: 2
      networks:
      - name: default
        pod: {}
      - name: wan
        multus:
          networkName: vlan10-dmz
      - name: lan1
        multus:
          networkName: vlan30-guest
      - name: lan2
        multus:
          networkName: vlan40-iot
```

## Verification

### Nach Deployment prüfen
```bash
# NetworkAttachmentDefinitions prüfen
kubectl get network-attachment-definitions -A

# Details einer Definition
kubectl describe network-attachment-definition vlan10-dmz

# Whereabouts IP-Vergabe prüfen
kubectl get ippools.whereabouts.cni.cncf.io -A

# In Pod/VM prüfen
kubectl exec -it <pod-name> -- ip addr show
```

### Test-Pod deployen
```bash
# Test Pod mit VLAN 10
cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: Pod
metadata:
  name: test-vlan10
  annotations:
    k8s.v1.cni.cncf.io/networks: vlan10-dmz
spec:
  containers:
  - name: test
    image: nicolaka/netshoot
    command: ["sleep", "infinity"]
EOF

# IP-Adressen prüfen
kubectl exec -it test-vlan10 -- ip addr show

# Erwartung:
# eth0: 10.1.x.x (Cilium)
# net1: 10.0.10.x (VLAN 10 DMZ)

# Gateway testen
kubectl exec -it test-vlan10 -- ping -I net1 10.0.10.1

# Cleanup
kubectl delete pod test-vlan10
```

## Troubleshooting

### NetworkAttachmentDefinition not found
```bash
# Prüfen ob Multus deployed
kubectl get pods -n kube-system | grep multus

# Prüfen ob CRDs installiert
kubectl get crd | grep network-attachment

# Falls fehlt: Multus neu deployen
kubectl apply -f https://raw.githubusercontent.com/k8snetworkplumbingwg/multus-cni/master/deployments/multus-daemonset.yml
```

### Pod bekommt keine IP
```bash
# Whereabouts IPAM Logs prüfen
kubectl logs -n kube-system -l app=whereabouts

# IP Pool prüfen
kubectl get ippools.whereabouts.cni.cncf.io -A

# IP Range exhausted? Config anpassen:
# - range_start/range_end erweitern
# - Subnet vergrößern
```

### VLAN Interface existiert nicht auf Node
```bash
# Prüfen ob bond0 und VLANs sichtbar
talosctl get links --nodes 10.0.100.103

# bond0 sollte existieren
# bond0.X werden von Multus dynamisch erstellt

# Falls bond0 fehlt: Talos config prüfen
talosctl get machineconfig --nodes 10.0.100.103
```

### macvlan Communication Issues

**Problem:** Pods können nicht mit Host/Gateway kommunizieren

**Ursache:** macvlan mode "bridge" isoliert Pods vom Host

**Lösung 1:** ipvlan statt macvlan nutzen:
```yaml
spec:
  config: |
    {
      "type": "ipvlan",  # Statt macvlan
      "mode": "l2",
      "master": "bond0.10"
    }
```

**Lösung 2:** macvlan mode "vepa" (wenn Switch unterstützt):
```yaml
spec:
  config: |
    {
      "type": "macvlan",
      "mode": "vepa",  # Statt bridge
      "master": "bond0.10"
    }
```

## IP-Range Anpassungen

Falls deine Subnetze anders sind, passe in `network-attachment-definitions.yaml` an:

```yaml
# Beispiel: VLAN 10 nutzt 192.168.10.0/24
"ipam": {
  "type": "whereabouts",
  "range": "192.168.10.0/24",      # ← Dein Subnet
  "range_start": "192.168.10.100", # ← Optional: Start-IP
  "range_end": "192.168.10.200",   # ← Optional: End-IP
  "gateway": "192.168.10.1",       # ← Dein Gateway
  "exclude": [                     # ← Optional: Reservierte IPs
    "192.168.10.50/32"
  ]
}
```

## Best Practices

1. **Namespaces:** Erstelle NetworkAttachmentDefinitions in den Namespaces wo sie genutzt werden
2. **Naming:** Klare Namen (vlanXX-purpose)
3. **IPAM:** Whereabouts für dynamische Vergabe, statische IPs nur wo nötig
4. **Security:** NetworkPolicies auch für Multus-Interfaces
5. **Testing:** Immer erst mit Test-Pods verifizieren
6. **Documentation:** IP-Ranges dokumentieren (z.B. in diesem README)

## Beispiel-Szenarien

### OPNsense Firewall VM
- WAN: VLAN 10 (DMZ)
- LAN: VLAN 30, 40, 50 (Guest, IoT, Lab)
- Management: VLAN 100 (Cluster)

### Monitoring Stack
- Prometheus: VLAN 200 (Monitoring)
- Exporters auf anderen VLANs

### Multi-Tenant Applications
- Frontend: VLAN 10 (Public)
- Backend: VLAN 100 (Internal)
- Database: VLAN 60 (Storage)

## Weitere Resourcen

- [Multus Documentation](https://github.com/k8snetworkplumbingwg/multus-cni)
- [Whereabouts IPAM](https://github.com/k8snetworkplumbingwg/whereabouts)
- [KubeVirt Networking](https://kubevirt.io/user-guide/virtual_machines/interfaces_and_networks/)
