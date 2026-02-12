# Quick Reference

常用資訊速查。

## Network

| Network | CIDR | Purpose |
|---------|------|---------|
| VCN | 10.0.0.0/16 | Virtual Cloud Network |
| Public Subnet | 10.0.0.0/24 | All nodes |
| Pod Network (Flannel) | 10.244.0.0/16 | Container networking |
| Service Network | 10.96.0.0/12 | Kubernetes ClusterIP |
| Control Plane | 10.0.0.3 (fixed) | API Server |

## Component Versions

| Component | Version |
|-----------|---------|
| Kubernetes | v1.32.x |
| Flannel | latest |
| ingress-nginx | v1.12.0 |
| cert-manager | v1.19.3 |
| ArgoCD | stable |

## Compute Allocation

| Role | OCPU | RAM |
|------|------|-----|
| Control Plane | 2 | 12 GB |
| Worker 1 | 1 | 6 GB |
| Worker 2 | 1 | 6 GB |
| **Total** | **4** | **24 GB** |

## Storage Budget

| Usage | Size |
|-------|------|
| 3x Boot Volume | 150 GB |
| 1x Block Volume (CP workspace) | 50 GB |
| **Total** | **200 GB (limit)** |

## Common Commands

```bash
# Terraform
cd terraform && tf-oci plan && tf-oci apply

# SSH
ssh oci-cp / ssh oci-worker-1 / ssh oci-worker-2

# cloud-init completion check
ssh ubuntu@<ip> 'cat /tmp/cloud-init-done'

# K8s cluster status
ssh oci-cp 'kubectl get nodes && kubectl get pods -A'

# NLB health check
./scripts/check-nlb.sh
```

## Credentials

| Credential | Location |
|------------|----------|
| OCI API key | `~/.ssh/oci_api_key.pem` |
| SSH key for VMs | `~/.ssh/id_rsa_oracle_cloud` |
| S3 credentials (tfstate) | `~/.aws/credentials` `[oci]` |
| Shell alias | `tf-oci` = `AWS_PROFILE=oci terraform` |

## Detailed References

- **[always-free-resources.md](always-free-resources.md)** — OCI Always Free 完整配額表
- **[requirements.md](requirements.md)** — 架構需求規格與設計決策
