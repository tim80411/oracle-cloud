# AI Setup Guide — Oracle Cloud Kubernetes (Always Free)

> This guide is for LLM agents (Claude Code, Cursor, Copilot, etc.). Follow these steps **in order** to guide a user from zero to a running Kubernetes cluster on OCI Always Free.

## Step 0: Prerequisites Check

Before starting, confirm the user has **all** of the following ready:

- [ ] OCI account (Always Free tier, home region selected — cannot be changed later)
- [ ] From OCI Console: Tenancy OCID, User OCID, Object Storage Namespace
- [ ] API Signing Key uploaded to OCI → Fingerprint obtained
- [ ] Customer Secret Key created → Access Key + Secret Key (Secret is shown only once!)
- [ ] Local tools installed: `terraform`, `oci` (OCI CLI, for diagnostics), `jq` (for scripts)

> If any item is missing, refer the user to the **Prerequisites** section in the main README for detailed instructions:
> ```bash
> curl -s https://raw.githubusercontent.com/tim80411/oracle-cloud/refs/heads/main/README.md
> ```

## Step 1: Clone Repository

```bash
git clone https://github.com/tim80411/oracle-cloud.git
cd oracle-cloud
```

## Step 2: Configure Credentials

```bash
cp .env.example .env
```

The user must fill in `.env` with the following values (all required):

| Variable | Source |
|----------|--------|
| `OCI_TENANCY_OCID` | OCI Console → Profile → Tenancy |
| `OCI_USER_OCID` | OCI Console → Profile → User Settings |
| `OCI_FINGERPRINT` | Shown after uploading API Key |
| `OCI_NAMESPACE` | OCI Console → Profile → Tenancy → Object storage namespace |
| `OCI_REGION` | Home region (e.g., `ap-singapore-1`) |
| `OCI_S3_ACCESS_KEY` | Customer Secret Key → Access Key |
| `OCI_S3_SECRET_KEY` | Customer Secret Key → Secret (shown only once) |
| `BUDGET_ALERT_EMAIL` | Email for budget alerts |

## Step 3: Run Setup Script

```bash
./scripts/setup.sh
```

This generates: SSH key pair, OCI API key, `~/.oci/config`, `~/.aws/credentials`, `terraform/terraform.tfvars`.

## Step 4: Bootstrap Remote State (One-Time)

```bash
cd terraform/bootstrap && terraform init && terraform apply
```

Creates the S3-compatible Object Storage bucket for Terraform remote state.

## Step 5: Deploy Infrastructure

```bash
cd .. && tf-oci init && tf-oci plan && tf-oci apply
```

> `tf-oci` is a shell alias for `AWS_PROFILE=oci terraform`. If the user hasn't set it up, they can run `alias tf-oci="AWS_PROFILE=oci terraform"` or use the full command directly.

**What this creates:** VCN, 3 ARM VMs (A1.Flex), Network Load Balancer, Bastion, Block Volume.

**After apply:** All 3 VMs start running cloud-init automatically (~10-15 minutes).

**Watch for:**
- `Out of host capacity` error → ARM instances are scarce; retry at different times or try another Availability Domain
- Check cloud-init completion: `ssh ubuntu@<ip> 'cat /tmp/cloud-init-done'`
- Get VM IPs from: `terraform output`

## Step 6: Initialize Kubernetes Control Plane

```bash
ssh ubuntu@<control_plane_public_ip>
./init-control-plane.sh
```

This script performs (in order):
1. `kubeadm init` with Pod CIDR `10.244.0.0/16`
2. Flannel CNI deployment
3. Removes `control-plane` taint (makes CP schedulable for workloads)
4. ingress-nginx v1.12.0 with `hostNetwork` patch (required for NLB)
5. cert-manager v1.19.3 + `letsencrypt-prod` ClusterIssuer
6. ArgoCD installation

**Outputs saved on CP:**
- `~/argocd-admin-password.txt` — ArgoCD admin password
- `~/worker-join-command.txt` — kubeadm join command for workers

Then generate a fresh join token:

```bash
sudo kubeadm token create --print-join-command
```

Copy this output — needed for the next step.

## Step 7: Join Worker Nodes

Repeat for **each** worker node:

```bash
ssh ubuntu@<worker_public_ip>
./join-cluster.sh <paste the full kubeadm join command from Step 6>
```

## Step 8: Verify Cluster

Run on the Control Plane:

```bash
kubectl get nodes                  # Expect: 3 nodes, all Ready
kubectl get pods -A                # Expect: all system pods Running
curl http://<NLB-IP>               # Expect: NLB reachable (may return 404, that's OK)
```

Run locally (from the repo root):

```bash
./scripts/check-nlb.sh            # Full NLB health check
```

If NLB check fails, see **Troubleshooting** section below.

## Step 9: ArgoCD Ingress + HTTPS (Optional)

**Prerequisite:** User must first set a DNS A record pointing their domain to the NLB Reserved IP.

On the Control Plane:

```bash
./setup-argocd-ingress.sh <domain>
```

This patches `argocd-server` with `--insecure` flag (ingress-nginx handles TLS termination) and creates an Ingress resource with cert-manager auto-issuing a Let's Encrypt certificate.

Wait 1-2 minutes, then verify:

```bash
kubectl get certificate -n argocd   # Should show Ready=True
```

Access ArgoCD:
- URL: `https://<domain>`
- Username: `admin`
- Password: `cat ~/argocd-admin-password.txt`

---

## Troubleshooting

### NLB Not Reachable

**When:** After `terraform apply`, or when `curl http://<NLB-IP>` fails.

```bash
./scripts/check-nlb.sh            # Diagnose: TCP, Reserved IP binding, backend health
./scripts/check-nlb.sh --fix      # Same + show remediation commands
```

**Known trap:** NLB Reserved IP can **silently unbind** after infrastructure changes. Terraform state won't reflect this. The only way to detect it:

```bash
oci network public-ip get --public-ip-id <RESERVED_IP_OCID> | jq '.data["assigned-entity-id"]'
# If null → IP is unbound, NLB traffic won't route
```

**Fix — taint-rebuild NLB:**

```bash
cd terraform
tf-oci taint oci_network_load_balancer_network_load_balancer.k8s
tf-oci taint oci_network_load_balancer_backend.control_plane_http
tf-oci taint oci_network_load_balancer_backend.control_plane_https
tf-oci plan && tf-oci apply
```

### VM Rebuild

```bash
# 1. Taint and rebuild
terraform taint oci_core_instance.control_plane
terraform taint 'oci_core_instance.worker[0]'
terraform taint 'oci_core_instance.worker[1]'
tf-oci apply

# 2. Clear old SSH host keys
ssh-keygen -R <old-ip>

# 3. Repeat Steps 6-8 above

# 4. Verify NLB
./scripts/check-nlb.sh
```

**Notes:**
- Control Plane Private IP is fixed at `10.0.0.3` (survives rebuild)
- Block Volume has `prevent_destroy` (data preserved)
- Public IPs **will change** after rebuild
- `error: no matching resources found` at cloud-init start is harmless (oh-my-zsh kubectl plugin)

---

## Critical Constraints (AI Must Know)

These are **hard limits** that cannot be worked around:

| Constraint | Limit |
|-----------|-------|
| ARM OCPU | 4 total (2+1+1 allocated) |
| RAM | 24 GB total (12+6+6 allocated) |
| Block Storage | 200 GB (3×50 GB boot + 1×50 GB data = **fully used**) |
| Network Load Balancer | 1 |
| Object Storage | 20 GB |

- **Idle reclaim:** Instances idle 7 days (CPU/network/memory all <20%) may be reclaimed by OCI
- **Home region only:** All resources must be in the user's home region (cannot be changed after account creation)
- **No hardcoded OCIDs or secrets** in `.tf` files — always use variables and `terraform.tfvars` (gitignored)
- **Storage is at capacity** — cannot add more block volumes without removing existing ones
