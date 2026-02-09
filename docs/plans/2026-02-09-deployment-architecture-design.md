# Deployment Architecture Design

## Overview

This document defines the full deployment architecture for the OCI Always Free K8s cluster. The goal is to make this repository the "text mirror" of the entire environment — everything needed to recreate the infrastructure and platform is captured here.

## Architecture Layers

```
Layer 3: Application (GitOps / ArgoCD)
         ArgoCD watches Git repo, auto-syncs K8s manifests

Layer 2: K8s Platform (Manual → future cloud-init)
         kubeadm cluster + Ingress + cert-manager + ArgoCD

Layer 1: Infrastructure (Terraform)
         VCN, Compute, NLB, Block Volume, Object Storage
```

## Layer 1: Infrastructure (Terraform)

### Existing Resources

| Resource | Description |
|----------|-------------|
| VCN + Subnet | 10.0.0.0/16, public subnet |
| 3x VM.Standard.A1.Flex | 1 control plane (2 OCPU/12 GB) + 2 workers (1 OCPU/6 GB each) |
| Network Load Balancer | Reserved public IP, TCP 80/443 listeners |
| Bastion Service | SSH management access |
| cloud-init scripts | Base packages + Homebrew + dotfiles (control plane) |

### New: Object Storage (Terraform Remote State)

- Create an OCI Object Storage bucket for `terraform.tfstate`
- Configure S3-compatible backend in `provider.tf`
- Prevents state file from being local-only
- Enables safe collaboration and state recovery

### New: Block Volume (Personal Workspace)

- 50 GB Block Volume attached to Control Plane instance
- Mounted as persistent personal workspace (e.g., `/data` or `/home/ubuntu`)
- Survives instance reclaim/recreation (OCI idle reclaim risk)
- Stores personal dotfiles, working files, SSH keys, project data
- NOT a K8s PersistentVolume — directly mounted at OS level

### Storage Budget

| Resource | Size | Notes |
|----------|------|-------|
| Control Plane boot volume | 50 GB | OCI minimum ~47 GB |
| Worker 1 boot volume | 50 GB | |
| Worker 2 boot volume | 50 GB | |
| Block Volume (workspace) | 50 GB | Attached to Control Plane |
| **Total** | **200 GB** | **Always Free limit: 200 GB (fully utilized)** |

## Layer 2: K8s Platform (Manual)

Initial setup is manual to build understanding. Steps to automate via cloud-init later.

### Installation Order

1. Install container runtime (containerd) on all 3 nodes
2. Install kubeadm, kubelet, kubectl on all 3 nodes
3. `kubeadm init` on control plane
4. Remove default taint on control plane (allow workload scheduling)
5. Install CNI plugin (Flannel or Calico)
6. `kubeadm join` on both workers
7. Install Nginx Ingress Controller
8. Install cert-manager + Let's Encrypt ClusterIssuer
9. Install ArgoCD
10. Point domain DNS to NLB public IP

### Future Automation

Once comfortable with the manual process, encode steps into `cloud-init/control-plane.yaml` and `cloud-init/base.yaml` so that `terraform apply` produces a fully working cluster.

## Layer 3: Application (GitOps)

### Tool: ArgoCD

- ArgoCD deployed inside the cluster (step 9 above)
- Watches this Git repository for K8s manifests
- Auto-syncs changes from Git to the cluster

### Repository Structure (planned)

```
oracle-cloud/
├── terraform/          # Layer 1: Infrastructure
│   ├── *.tf
│   └── cloud-init/
├── k8s/                # Layer 3: Application manifests
│   ├── argocd/         # ArgoCD configuration
│   └── apps/           # Application deployments
└── docs/
```

### Database

- OCI Always Free MySQL HeatWave (managed service, outside K8s)
- Applications connect via VCN internal networking

## Design Decisions

1. **Block Volume for workspace, not K8s PV** — Applications are stateless; DB is managed service; Block Volume protects personal data from instance reclaim
2. **Object Storage for tfstate** — Remote state prevents local-only risk; enables recovery
3. **Manual K8s setup first** — Build understanding before automating; cloud-init automation planned for later
4. **ArgoCD over Flux** — Web UI provides better visibility despite higher resource usage
5. **OCI MySQL HeatWave over in-cluster DB** — Free managed service; no PV needed; reduces cluster complexity
