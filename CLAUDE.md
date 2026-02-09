# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

Self-managed Kubernetes cluster on Oracle Cloud Infrastructure (OCI) using **only Always Free resources**. The repo serves as the "text mirror" of the entire environment — all infrastructure is defined as code.

## Architecture

3-layer deployment:
- **Layer 1 (Terraform):** VCN, 3x ARM VMs (A1.Flex), NLB, Bastion, Block Volume, Object Storage
- **Layer 2 (Manual → future cloud-init):** kubeadm K8s cluster, Ingress, cert-manager, ArgoCD
- **Layer 3 (GitOps):** ArgoCD syncs application manifests from this repo

Compute: 1 control plane (2 OCPU/12 GB, also schedulable) + 2 workers (1 OCPU/6 GB each) = 4 OCPU/24 GB total (Always Free limit).

## Repository Structure

- `terraform/` — Main Terraform configuration (the active IaC)
- `terraform/bootstrap/` — Separate Terraform config to create the Object Storage bucket for remote state; must be applied before the main config
- `terraform/cloud-init/` — Cloud-init YAML scripts for VM initialization
- `docs/` — Architecture requirements and Always Free resource reference
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
- **Storage budget is fully utilized:** 3×50 GB boot volumes + 1×50 GB block volume = 200 GB.
- **OCI idle reclaim risk:** Instances idle for 7 days (CPU/network/memory all <20%) may be reclaimed. The Block Volume on the control plane survives reclaim.
- **Region:** ap-singapore-1. All Always Free resources must be in the home region.
- **No hardcoded OCIDs or secrets in .tf files.** Use variables and `terraform.tfvars` (gitignored).
- **Budget guard:** $1 USD/month budget with alerts on any actual or forecasted spend. Configured in `terraform/budget.tf`.

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
