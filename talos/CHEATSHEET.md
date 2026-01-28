# Talos CLI Cheatsheet

Quick reference for common Talos operations.

## Environment Setup

```bash
# Set talosconfig location
export TALOSCONFIG=$(pwd)/secrets/talosconfig

# Common node IPs
export HOST01=10.0.100.101
export HOST02=10.0.100.102
export HOST03=10.0.100.103
export VIP=10.0.100.111
```

## Cluster Management

### Bootstrap & Join

```bash
# Generate configs
./scripts/build-talos-configs.sh all

# Apply config (first time, use --insecure)
talosctl apply-config --insecure --nodes ${HOST03} --file configs/host03.yaml

# Bootstrap Kubernetes (only on first controlplane)
talosctl bootstrap --nodes ${HOST03} --endpoints ${HOST03}

# Get kubeconfig
talosctl kubeconfig --nodes ${VIP} --endpoints ${VIP}

# Join worker nodes
talosctl apply-config --insecure --nodes ${HOST01} --file configs/host01.yaml
talosctl apply-config --insecure --nodes ${HOST02} --file configs/host02.yaml
```

### Health Checks

```bash
# Check cluster health
talosctl health --server --nodes ${HOST03}

# Check all services
talosctl services --nodes ${HOST03}

# Check etcd health
talosctl etcd status --nodes ${HOST03}

# Check cluster members
talosctl get members --nodes ${HOST03}
```

## Node Operations

### Information

```bash
# Node version
talosctl version --nodes ${HOST03}

# Node config
talosctl get machineconfig --nodes ${HOST03}

# System info
talosctl get systeminfo --nodes ${HOST03}

# Disk info
talosctl disks --nodes ${HOST03}

# Memory info
talosctl read /proc/meminfo --nodes ${HOST03}

# CPU info
talosctl read /proc/cpuinfo --nodes ${HOST03}
```

### Logs

```bash
# All logs
talosctl logs --nodes ${HOST03}

# Service-specific logs
talosctl logs kubelet --nodes ${HOST03}
talosctl logs etcd --nodes ${HOST03}
talosctl logs apid --nodes ${HOST03}

# Follow logs
talosctl logs -f --nodes ${HOST03}

# Kernel logs
talosctl dmesg --nodes ${HOST03}
```

### Shell Access

```bash
# Interactive shell (requires extension)
talosctl shell --nodes ${HOST03}

# Run command
talosctl read /proc/cmdline --nodes ${HOST03}
```

## Networking

### Network Information

```bash
# List interfaces
talosctl get links --nodes ${HOST03}

# Show addresses
talosctl get addresses --nodes ${HOST03}

# Show routes
talosctl get routes --nodes ${HOST03}

# Network configuration
talosctl get networkconfig --nodes ${HOST03}

# Network status
talosctl get networkstatus --nodes ${HOST03}
```

### Connectivity Tests

```bash
# Ping from node
talosctl exec --nodes ${HOST03} -- ping -c 4 8.8.8.8

# Trace route
talosctl exec --nodes ${HOST03} -- traceroute 8.8.8.8

# Check DNS
talosctl exec --nodes ${HOST03} -- nslookup kubernetes.default.svc.cluster.local
```

## Configuration Updates

### Apply Config Changes

```bash
# Edit config
vim configs/host03.yaml

# Apply changes
talosctl apply-config --nodes ${HOST03} --file configs/host03.yaml

# Force apply (dangerous!)
talosctl apply-config --nodes ${HOST03} --file configs/host03.yaml --mode=staged

# Apply and reboot immediately
talosctl apply-config --nodes ${HOST03} --file configs/host03.yaml --mode=reboot
```

### Patch Config

```bash
# Patch machine config
talosctl patch machineconfig --nodes ${HOST03} --patch '[{"op": "add", "path": "/machine/time/servers", "value": ["time.cloudflare.com"]}]'
```

## Upgrades

### Talos Upgrade

```bash
# Check current version
talosctl version --nodes ${HOST03}

# Upgrade Talos (example to v1.9.4)
talosctl upgrade --nodes ${HOST03} --image ghcr.io/siderolabs/installer:v1.9.4

# Upgrade with preserve (don't wipe ephemeral partition)
talosctl upgrade --nodes ${HOST03} --image ghcr.io/siderolabs/installer:v1.9.4 --preserve

# Monitor upgrade
talosctl dmesg --nodes ${HOST03} -f
```

### Kubernetes Upgrade

```bash
# Check available versions
talosctl upgrade-k8s --nodes ${HOST03} --dry-run

# Upgrade Kubernetes (example to 1.32.0)
talosctl upgrade-k8s --nodes ${HOST03} --to 1.32.0

# Follow upgrade progress
kubectl get nodes -w
```

## Maintenance

### Reboot

```bash
# Graceful reboot
talosctl reboot --nodes ${HOST03}

# Force reboot (if hung)
talosctl reboot --nodes ${HOST03} --mode=powercycle
```

### Reset

```bash
# Graceful reset (keeps data)
talosctl reset --graceful --nodes ${HOST03}

# Factory reset (wipes everything)
talosctl reset --wipe --nodes ${HOST03}

# Reset and reboot
talosctl reset --reboot --nodes ${HOST03}
```

### Shutdown

```bash
# Graceful shutdown
talosctl shutdown --nodes ${HOST03}

# Force shutdown
talosctl shutdown --nodes ${HOST03} --force
```

## Backup & Recovery

### etcd Backup

```bash
# Create snapshot
talosctl etcd snapshot --nodes ${HOST03} > etcd-snapshot-$(date +%Y%m%d-%H%M%S).db

# List etcd members
talosctl etcd members --nodes ${HOST03}

# Check etcd status
talosctl etcd status --nodes ${HOST03}
```

### etcd Recovery

```bash
# Recover from snapshot
talosctl bootstrap recover --source ./etcd-snapshot.db --nodes ${HOST03}
```

### Config Backup

```bash
# Backup all configs
mkdir -p backup/$(date +%Y%m%d)
cp configs/*.yaml backup/$(date +%Y%m%d)/
cp secrets/secrets.yaml backup/$(date +%Y%m%d)/
cp secrets/talosconfig backup/$(date +%Y%m%d)/
```

## Debugging

### Container Runtime

```bash
# List containers
talosctl containers --nodes ${HOST03}

# List containers (Kubernetes)
talosctl containers -k --nodes ${HOST03}

# Container logs
talosctl logs <container-id> --nodes ${HOST03}
```

### System Resources

```bash
# Show disk usage
talosctl df --nodes ${HOST03}

# Show running processes
talosctl ps --nodes ${HOST03}

# Show resource usage
talosctl stats --nodes ${HOST03}
```

### Packet Capture

```bash
# Capture packets on interface
talosctl pcap --interface bond0.100 --nodes ${HOST03} > capture.pcap

# Analyze with Wireshark
wireshark capture.pcap
```

### Kernel Modules

```bash
# List loaded modules
talosctl read /proc/modules --nodes ${HOST03}

# Check specific module
talosctl read /sys/module/bonding/parameters/mode --nodes ${HOST03}
```

## Cilium Operations

### Cilium Status

```bash
# Via kubectl
kubectl exec -n kube-system ds/cilium -- cilium status

# Detailed status
kubectl exec -n kube-system ds/cilium -- cilium status --verbose

# BGP status
kubectl exec -n kube-system ds/cilium -- cilium bgp routes
```

### Cilium Connectivity

```bash
# Connectivity test
kubectl exec -n kube-system ds/cilium -- cilium connectivity test

# Endpoint list
kubectl exec -n kube-system ds/cilium -- cilium endpoint list

# Service list
kubectl exec -n kube-system ds/cilium -- cilium service list
```

### Hubble

```bash
# Watch flows
kubectl exec -n kube-system ds/cilium -- hubble observe --follow

# Watch specific namespace
kubectl exec -n kube-system ds/cilium -- hubble observe --namespace default --follow

# Show dropped packets
kubectl exec -n kube-system ds/cilium -- hubble observe --verdict DROPPED
```

## Useful Aliases

Add to your `~/.bashrc` or `~/.zshrc`:

```bash
# Talos aliases
alias t='talosctl'
alias tn='talosctl --nodes'
alias tl='talosctl logs'
alias ts='talosctl services'
alias th='talosctl health'

# Talos with common node
alias t1='talosctl --nodes 10.0.100.101'
alias t2='talosctl --nodes 10.0.100.102'
alias t3='talosctl --nodes 10.0.100.103'

# Kubernetes aliases
alias k='kubectl'
alias kgp='kubectl get pods -A'
alias kgn='kubectl get nodes -o wide'
alias kgs='kubectl get svc -A'
alias kd='kubectl describe'
alias kl='kubectl logs -f'

# Cilium alias
alias cilium='kubectl exec -n kube-system ds/cilium --'
```

## Emergency Procedures

### Lost API Access

```bash
# Connect directly to node
talosctl --nodes ${HOST03} get kubeconfig

# Or bootstrap again (if cluster is lost)
talosctl bootstrap --nodes ${HOST03}
```

### Node Not Responding

```bash
# Check with direct connection
talosctl --talosconfig=<(talosctl gen config --output-types talosconfig homelab https://${HOST03}:6443) --nodes ${HOST03} version

# Physical console access
# Boot from USB and reset node
```

### etcd Corruption

```bash
# Stop etcd member
talosctl etcd forfeit-leadership --nodes ${HOST03}

# Remove member
talosctl etcd leave --nodes ${HOST03}

# Re-join cluster
talosctl apply-config --nodes ${HOST03} --file configs/host03.yaml
```

## Tips & Best Practices

1. **Always backup** before major changes
2. **Test configs** with `--dry-run` when possible
3. **Use VIP** for API access (not individual node IPs)
4. **Monitor logs** during upgrades
5. **Keep talosconfig** secure (contains cluster credentials)
6. **Use Git** for config versioning
7. **Document** any manual changes
8. **Upgrade one node at a time** for HA

## Resources

- [Talos Documentation](https://www.talos.dev/latest/)
- [Talos GitHub](https://github.com/siderolabs/talos)
- [Talos Slack](https://slack.dev.talos-systems.io/)
