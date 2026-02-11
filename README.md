# Oracle Cloud Kubernetes (Always Free)

Self-managed Kubernetes cluster on Oracle Cloud Infrastructure (OCI) using **only Always Free resources**.

## Architecture

3-layer deployment:
- **Layer 1 (Terraform):** VCN, 3x ARM VMs (A1.Flex), NLB, Bastion, Block Volume, Object Storage
- **Layer 2 (cloud-init + scripts):** kubeadm K8s cluster, Flannel CNI, ingress-nginx, cert-manager, ArgoCD
- **Layer 3 (GitOps):** ArgoCD syncs application manifests from this repo

Compute allocation: 1 control plane (2 OCPU/12 GB) + 2 workers (1 OCPU/6 GB each) = 4 OCPU/24 GB total.

### Network

| Network | CIDR | Purpose |
|---------|------|---------|
| VCN | 10.0.0.0/16 | Virtual Cloud Network |
| Public Subnet | 10.0.0.0/24 | All nodes |
| Control Plane | 10.0.0.3 (fixed) | API Server |
| Pod Network (Flannel) | 10.244.0.0/16 | Container networking |
| Service Network | 10.96.0.0/12 | Kubernetes ClusterIP |

### Component Versions

| Component | Version |
|-----------|---------|
| Kubernetes | v1.32.x |
| Flannel | latest |
| ingress-nginx | v1.12.0 |
| cert-manager | v1.19.3 |
| ArgoCD | stable |

## Prerequisites

### 1. Register OCI Account

1. Go to [Oracle Cloud Free Tier](https://www.oracle.com/cloud/free/)
2. Click "Start for free" and complete registration
3. **Important:** Select your home region carefully (e.g., `ap-singapore-1`) — Always Free resources are only available in your home region and cannot be changed later

### 2. Collect Required Information from OCI Console

After logging into the OCI Console, collect the following:

| Item | How to Find |
|------|-------------|
| Tenancy OCID | Profile icon (top-right) → Tenancy → Copy OCID |
| User OCID | Profile icon → User Settings → Copy OCID |
| Object Storage Namespace | Profile icon → Tenancy → "Object storage namespace" |
| API Key Fingerprint | (After step 3) Profile icon → User Settings → API Keys |
| S3 Access Key | (After step 4) Profile icon → User Settings → Customer Secret Keys |

### 3. Generate & Upload API Signing Key

```bash
# Generate key (setup script can also do this)
openssl genrsa -out ~/.ssh/oci_api_key.pem 2048
openssl rsa -pubout -in ~/.ssh/oci_api_key.pem -out ~/.ssh/oci_api_key_public.pem
```

Upload to OCI:
1. Profile icon → User Settings → API Keys → Add API Key
2. Paste contents of `~/.ssh/oci_api_key_public.pem`
3. Note the **Fingerprint** displayed

### 4. Create Customer Secret Key (for S3-compatible access)

1. Profile icon → User Settings → Customer Secret Keys → Generate Secret Key
2. **Copy the secret key immediately** (shown only once!)
3. Note the Access Key from the list

### 5. Install Required Tools

```bash
# Terraform (macOS)
brew install terraform

# Optional: Shell alias for OCI S3 backend
echo 'alias tf-oci="AWS_PROFILE=oci terraform"' >> ~/.zshrc
source ~/.zshrc
```

## Deployment

### Layer 1: Infrastructure (Terraform)

```bash
# 1. Clone & configure
git clone <repository-url>
cd oracle-cloud
cp .env.example .env
vim .env  # Edit with your OCI credentials

# 2. Run setup script
./scripts/setup.sh

# 3. Bootstrap remote state bucket (one-time)
cd terraform/bootstrap
terraform init && terraform apply

# 4. Deploy main infrastructure
cd ..
tf-oci init && tf-oci plan && tf-oci apply
```

### Layer 2: Kubernetes Setup

After `terraform apply`, cloud-init automatically prepares all nodes (~10-15 minutes).

```bash
# 1. Wait for cloud-init to complete on Control Plane
ssh ubuntu@<cp-public-ip> 'cat /tmp/cloud-init-done'

# 2. Initialize K8s cluster (kubeadm init, Flannel, ingress-nginx, cert-manager, ArgoCD)
ssh ubuntu@<cp-public-ip>
./init-control-plane.sh

# 3. Wait for cloud-init to complete on Workers
ssh ubuntu@<w1-public-ip> 'cat /tmp/cloud-init-done'
ssh ubuntu@<w2-public-ip> 'cat /tmp/cloud-init-done'

# 4. Join workers to cluster
ssh ubuntu@<w1-public-ip>
./join-cluster.sh 10.0.0.3

ssh ubuntu@<w2-public-ip>
./join-cluster.sh 10.0.0.3
```

### Layer 3: GitOps (ArgoCD)

ArgoCD is installed by `init-control-plane.sh`. Admin password is saved to `~/argocd-admin-password.txt` on the Control Plane.

Configure DNS A records pointing to the NLB Reserved IP, then set up ArgoCD to sync application manifests from this repo.

### Verification

```bash
kubectl get nodes                    # 3 nodes Ready
kubectl get pods -A                  # All system pods Running
kubectl get clusterissuer            # letsencrypt-prod Ready
curl http://<NLB-IP>                 # NLB reachable
```

## VM Rebuild

```bash
# 1. Taint VMs for rebuild (Block Volume is protected with prevent_destroy)
terraform taint oci_core_instance.control_plane
terraform taint 'oci_core_instance.worker[0]'
terraform taint 'oci_core_instance.worker[1]'
tf-oci apply

# 2. Clean old SSH host keys
ssh-keygen -R <old-cp-ip>
ssh-keygen -R <old-w1-ip>
ssh-keygen -R <old-w2-ip>

# 3. Repeat Layer 2 setup above
```

**Notes:**
- Control Plane Private IP is fixed at `10.0.0.3` (survives rebuild)
- NLB Reserved IP is static (survives rebuild)
- Block Volume data is preserved (`prevent_destroy` enabled)
- Public IPs will change — update SSH configs accordingly
- cloud-init takes ~10-15 minutes, check with `cat /tmp/cloud-init-done`

## Key Constraints

- **Always Free limits are hard ceilings:** 4 ARM OCPU, 24 GB RAM, 200 GB block storage, 1 NLB, 20 GB object storage
- **Storage fully utilized:** 3x50 GB boot volumes + 1x50 GB block volume = 200 GB
- **Idle reclaim risk:** Instances idle for 7 days (CPU/network/memory all <20%) may be reclaimed
- **Home region only:** All Always Free resources must be in your home region
- **Budget guard:** $1 USD/month budget with alerts configured

## Repository Structure

```
terraform/                              # Main Terraform configuration
terraform/bootstrap/                    # Remote state bucket setup (apply first)
terraform/cloud-init/
  k8s-control-plane.yaml                # CP: iptables, containerd, kubeadm, Homebrew, init script
  k8s-base.yaml                         # Worker: iptables, containerd, kubeadm, join script
scripts/
  setup.sh                              # Initial credential and config setup
docs/
  layer2-manual-setup.md                # Step-by-step K8s setup guide
  layer2-installation-report.md         # Detailed installation report with K8s concepts
  troubleshooting.md                    # Common issues and solutions
  2026-02-10-nlb-troubleshooting.md     # NLB-specific troubleshooting
  always-free-resources.md              # OCI Always Free reference
  plans/                                # Design documents
```

## Useful Commands

```bash
# Validate Terraform config
cd terraform && terraform validate

# Format check
cd terraform && terraform fmt -check -recursive

# Destroy infrastructure
cd terraform && tf-oci destroy
```

## Troubleshooting

See **[Troubleshooting Guide](docs/troubleshooting.md)** for detailed steps.

| Issue | Solution |
|-------|---------|
| ARM Instance "Out of capacity" | Retry at different times, try other AD |
| API Key auth failure | Verify fingerprint, check `~/.oci/config` |
| Permission Denied | Verify IAM policies, join Administrators group |
| NLB Backend unhealthy | Verify Ingress uses hostNetwork on 80/443 |
| NLB Health OK but external timeout | Check Reserved IP binding, use tcpdump |
| iptables blocking traffic | cloud-init should handle this; check `iptables -L INPUT -n` |
| Ingress not listening on 80/443 | `init-control-plane.sh` patches hostNetwork automatically |
| NLB Reserved IP binding lost | Taint-rebuild NLB (see NLB troubleshooting doc) |

## References

- [OCI Always Free Resources](https://docs.oracle.com/en-us/iaas/Content/FreeTier/freetier_topic-Always_Free_Resources.htm)
- [OCI Terraform Provider](https://registry.terraform.io/providers/oracle/oci/latest/docs)
