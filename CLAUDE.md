# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

Self-managed Kubernetes cluster on Oracle Cloud Infrastructure (OCI) using **only Always Free resources**. The repo serves as the "text mirror" of the entire environment — all infrastructure is defined as code.

## Architecture

3-layer deployment:
- **Layer 1 (Terraform):** VCN, 3x ARM VMs (A1.Flex), NLB, Bastion, Block Volume, Object Storage — fully automated
- **Layer 2 (cloud-init + scripts):** kubeadm K8s cluster, Flannel CNI, ingress-nginx, cert-manager, ArgoCD — cloud-init automates env prep, scripts automate K8s init
- **Layer 3 (GitOps):** ArgoCD App-of-Apps syncs from private `k8s-apps` repo via SSH deploy key

Compute: 1 control plane (2 OCPU/12 GB, also schedulable) + 2 workers (1 OCPU/6 GB each) = 4 OCPU/24 GB total (Always Free limit).

### Layer 2 Setup Flow

cloud-init automatically installs: iptables rules, kernel modules, containerd, kubeadm/kubelet/kubectl.
Then manually run scripts:
1. Control Plane: `./init-control-plane.sh` (kubeadm init, Flannel, ingress-nginx, cert-manager, ArgoCD)
2. On CP: `sudo kubeadm token create --print-join-command` → copy the output
3. Workers: `./join-cluster.sh <kubeadm-join-command>` (paste the join command from step 2)
4. ArgoCD Ingress: `./setup-argocd-ingress.sh <domain>` (Ingress + TLS via cert-manager, run on CP after DNS A record is set)

**Design decision:** ArgoCD Ingress script is deployed via cloud-init `write_files` but not auto-executed, because domain is a user choice.

### Component Versions

| Component | Version |
|-----------|---------|
| Kubernetes | v1.32.x |
| Flannel | latest |
| ingress-nginx | v1.12.0 |
| cert-manager | v1.19.3 |
| ArgoCD | stable |

## Repository Structure

- `terraform/` — Main Terraform configuration (the active IaC)
- `terraform/bootstrap/` — Separate Terraform config to create the Object Storage bucket for remote state; must be applied before the main config
- `terraform/cloud-init/k8s-control-plane.yaml` — Control Plane cloud-init (iptables, containerd, kubeadm, Homebrew, dotfiles, init script)
- `terraform/cloud-init/k8s-base.yaml` — Worker node cloud-init (iptables, containerd, kubeadm, join script)
- `scripts/` — Utility scripts (not deployed by cloud-init)
- `docs/` — Architecture requirements, troubleshooting, and Always Free resource reference
- `docs/plans/` — Design documents
- `main.tf` — Legacy OCI-exported config (gitignored, not used)

## Commands

```bash
# Bootstrap (one-time): create tfstate bucket
cd terraform/bootstrap && terraform init && terraform apply

# Main infrastructure (tf-oci = AWS_PROFILE=oci terraform)
cd terraform && tf-oci init && tf-oci plan && tf-oci apply

# Validate config
cd terraform && terraform validate

# Format check
cd terraform && terraform fmt -check -recursive
```

## Key Constraints

- **Always Free limits are hard ceilings.** 4 ARM OCPU, 24 GB RAM, 200 GB block storage, 1 NLB, 20 GB object storage. Check `docs/always-free-resources.md` before adding resources.
- **Storage budget is fully utilized:** 3x50 GB boot volumes + 1x50 GB block volume = 200 GB.
- **OCI idle reclaim risk:** Instances idle for 7 days (CPU/network/memory all <20%) may be reclaimed. The Block Volume on the control plane survives reclaim.
- **Region:** ap-singapore-1. All Always Free resources must be in the home region.
- **No hardcoded OCIDs or secrets in .tf files.** Use variables and `terraform.tfvars` (gitignored).
- **Budget guard:** $1 USD/month budget with alerts on any actual or forecasted spend. Configured in `terraform/budget.tf`.
- **Control Plane Private IP is fixed at `10.0.0.3`.** Hardcoded in `compute.tf` to ensure stability across rebuilds.
- **Block Volume has `prevent_destroy`.** Must use `terraform state rm` if intentional deletion is needed.

## VM Rebuild Notes

- **OCI metadata change = VM force replace.** Editing cloud-init content triggers VM destruction/recreation. Use `terraform taint` for intentional rebuilds.
- **NLB Reserved IP may lose binding** after infrastructure changes. Verify with `curl http://<NLB-IP>`. Fix by taint-rebuilding NLB only (see `docs/2026-02-10-nlb-troubleshooting.md`).
- **SSH host keys change** on VM rebuild. Run `ssh-keygen -R <old-ip>` before reconnecting. Also update `~/.ssh/config` HostName entries (`oci-cp`, `oci-worker-1`, `oci-worker-2`) with new public IPs from `terraform output`.
- **cloud-init takes ~10-15 minutes.** Check completion: `ssh ubuntu@<ip> 'cat /tmp/cloud-init-done'`.

## NLB Diagnostic Procedure

**When to run:** After `terraform apply`, or whenever `curl http://<NLB-IP>` fails unexpectedly.

**Automated check:**
```bash
./scripts/check-nlb.sh          # check only
./scripts/check-nlb.sh --fix    # check + show remediation commands
```

**Manual equivalent (if CLI tools unavailable):**
```bash
# 1. TCP connectivity
curl --max-time 5 http://<NLB_IP>:80

# 2. Reserved IP binding (the silent failure — Terraform won't catch this)
oci network public-ip get --public-ip-id <RESERVED_IP_OCID> | jq '.data["assigned-entity-id"]'
# If null → IP is unbound, NLB traffic won't route

# 3. Backend health
oci nlb backend-set-health get \
  --backend-set-name k8s-ingress-backend-set \
  --network-load-balancer-id <NLB_OCID> | jq '.data.status'
```

**Fix (if Reserved IP is unbound or NLB unreachable):**
```bash
cd terraform
tf-oci taint oci_network_load_balancer_network_load_balancer.k8s
tf-oci taint oci_network_load_balancer_backend.control_plane_http
tf-oci taint oci_network_load_balancer_backend.control_plane_https
tf-oci plan && tf-oci apply
```

## init-control-plane.sh Execution Notes

- **`error: no matching resources found` at script start is harmless.** Caused by oh-my-zsh kubectl plugin trying to access cluster before kubeconfig is set. The error appears before the script runs but doesn't affect execution.
- **Script uses `wait_for_pods()` helper to prevent SSH timeout.** Outputs progress dots every 5 seconds during `kubectl wait` operations, keeping the SSH connection alive.
- **If script is interrupted, components can be installed manually.** Check what's already installed with `kubectl get pods -A`, then run remaining kubectl apply commands individually.

## OCI Ubuntu Image Gotchas

- **iptables default REJECT rules** block all non-SSH traffic. cloud-init fixes this by adding ACCEPT rules for VCN CIDR (10.0.0.0/24) and Pod CIDR (10.244.0.0/16) to INPUT, and removing the REJECT rule from FORWARD chain.
- **iptables INSERT position is critical:** OCI Ubuntu has REJECT at position 5 in INPUT chain. Must use `iptables -I INPUT 5` to insert BEFORE the REJECT rule. Using `-I INPUT 9` or higher positions will effectively append after REJECT, making rules useless.
- **Port 80/443 must be explicitly opened** in iptables for external NLB traffic (done in k8s-control-plane.yaml only).
- **ingress-nginx needs hostNetwork patch** for NLB to reach pods directly on port 80/443 (done in init-control-plane.sh).
- **cloud-init YAML gotcha:** Strings containing `: ` (colon+space) in runcmd must be wrapped in single quotes, e.g., `'echo "Next step: do something"'`. Otherwise YAML parses it as a dict and cloud-init fails silently.
- **write_files with `owner: ubuntu:ubuntu` requires `defer: true`:** The ubuntu user may not exist during early cloud-init stages. Add `defer: true` to delay file creation until final stage when user is guaranteed to exist.

## Credentials

- **OCI API key:** `~/.ssh/oci_api_key.pem` (referenced by `~/.oci/config`)
- **SSH key for VMs:** `~/.ssh/id_rsa_oracle_cloud` / `~/.ssh/id_rsa_oracle_cloud.pub`
- **S3-compatible credentials (remote state):** `~/.aws/credentials` under `[oci]` profile
- **Shell alias:** `tf-oci` = `AWS_PROFILE=oci terraform` (defined in `~/.zshrc`)

## Terraform Conventions

- Provider: `oracle/oci >= 5.0.0`
- All resources use `local.compartment_id` (equals `var.tenancy_ocid` for Always Free)
- Availability domain sourced from `data.oci_identity_availability_domains.ads`
- Ubuntu 24.04 ARM image sourced dynamically from `data.oci_core_images.ubuntu_arm`
- Section headers use `# ──────` comment blocks

## Network Architecture

| Network | CIDR | Purpose |
|---------|------|---------|
| VCN | 10.0.0.0/16 | Virtual Cloud Network |
| Public Subnet | 10.0.0.0/24 | All nodes |
| Pod Network (Flannel) | 10.244.0.0/16 | Container networking |
| Service Network | 10.96.0.0/12 | Kubernetes ClusterIP |
| Control Plane | 10.0.0.3 (fixed) | API Server |

## Ingress & TLS

- **ArgoCD Ingress** is configured via `~/setup-argocd-ingress.sh <domain>` on CP (deployed by cloud-init `write_files`, not auto-executed)
- **TLS:** Auto-managed by cert-manager + Let's Encrypt (letsencrypt-prod ClusterIssuer, HTTP-01 challenge)
- **ArgoCD server runs with `--insecure` flag** — ingress-nginx handles TLS termination
- **To check current Ingress domain:** `kubectl get ingress -n argocd` on the control plane
