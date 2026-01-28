# k8s-homelab-gitops

> GitOps-managed bare-metal Kubernetes homelab with Talos Linux, Cilium CNI, and automated ArgoCD deployment

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)
[![Kubernetes](https://img.shields.io/badge/Kubernetes-Talos-326CE5?logo=kubernetes)](https://talos.dev/)
[![ArgoCD](https://img.shields.io/badge/GitOps-ArgoCD-EF7B4D?logo=argo)](https://argoproj.github.io/cd/)
[![Cilium](https://img.shields.io/badge/CNI-Cilium-F8C517?logo=cilium)](https://cilium.io/)

## Why this stack
- Talos: immutable, API-only, minimal attack surface
- Cilium: eBPF performance, Gateway API, kube-proxy replacement
- ArgoCD: full GitOps automation from bootstrap
- Longhorn + KubeVirt: storage and VMs on the same cluster

## Features
- 3-node HA (all nodes are control plane + worker)
- Cilium + Hubble + Gateway API
- ArgoCD App-of-Apps (sync waves)
- Multus for multi-NIC pods/VMs
- Longhorn storage on data disk

## Quick Start
```bash
git clone https://github.com/Berndinox/k8s-homelab-gitops
cd k8s-homelab-gitops/talos

cp secrets.env.example secrets.env
nano secrets.env

./scripts/build-talos-configs.sh all

talosctl apply-config --insecure --nodes 10.0.100.103 --file configs/host03.yaml
talosctl bootstrap --nodes 10.0.100.103 --endpoints 10.0.100.103
talosctl kubeconfig --nodes 10.0.100.111

talosctl apply-config --insecure --nodes 10.0.100.101 --file configs/host01.yaml
talosctl apply-config --insecure --nodes 10.0.100.102 --file configs/host02.yaml
```

## Repo Layout
- `talos/` Talos configs + scripts
- `bootstrap/` ArgoCD root app
- `argocd-apps/` app-of-apps definitions
- `infrastructure/` core components
- `apps/` workloads

## Docs
- Install: `talos/INSTALL.md`
- Troubleshooting: `talos/COMMON-ISSUES.md`
- Talos overview: `talos/README.md`
- Infra/apps: `infrastructure/README.md`, `apps/README.md`

## Hardware (short)
- 3x servers, 2x NVMe (small OS + large data), 2x 10G NICs (LACP), VT-x/AMD-V

## License
MIT (see `LICENSE`)

## Disclaimer
Homelab only, no warranty.
