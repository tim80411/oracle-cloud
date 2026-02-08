# OCI Kubernetes Infrastructure (Always Free)

Terraform configuration for a self-managed Kubernetes cluster on Oracle Cloud Infrastructure, using only Always Free resources.

## Topology

```
                        Internet
                           |
                           v
                 +--------------------+
                 |  Reserved Public IP |
                 +--------------------+
                           |
                 +--------------------+
                 | Network Load       |
                 | Balancer (NLB)     |
                 | TCP 80 / TCP 443   |
                 +--------------------+
                           |
     ┌─────────────────────────────────────────────┐
     │  VCN 10.0.0.0/16                            │
     │  ┌────────────────────────────────────────┐  │
     │  │  Public Subnet 10.0.0.0/24             │  │
     │  │                                        │  │
     │  │  ┌──────────────────────────────────┐  │  │
     │  │  │  K8s Control Plane               │  │  │
     │  │  │  VM.Standard.A1.Flex (Arm)       │  │  │
     │  │  │  2 OCPU / 12 GB RAM              │  │  │
     │  │  │  + Ingress Controller            │  │  │
     │  │  │  + Schedulable for workloads     │  │  │
     │  │  └──────────┬───────────┬───────────┘  │  │
     │  │             |           |              │  │
     │  │     ┌───────┴──┐  ┌────┴───────┐      │  │
     │  │     │ Worker 1 │  │ Worker 2   │      │  │
     │  │     │ A1.Flex  │  │ A1.Flex    │      │  │
     │  │     │ 1 OCPU   │  │ 1 OCPU     │      │  │
     │  │     │ 6 GB RAM │  │ 6 GB RAM   │      │  │
     │  │     └──────────┘  └────────────┘      │  │
     │  └────────────────────────────────────────┘  │
     │                                              │
     │  Internet Gateway (outbound)                 │
     │  OCI Bastion Service (SSH management)        │
     └──────────────────────────────────────────────┘
```

## Resource Allocation

| Resource | Spec | Free Limit | Used |
|----------|------|------------|------|
| Arm OCPU | 4 total (2+1+1) | 4 OCPU | 100% |
| Arm RAM | 24 GB total (12+6+6) | 24 GB | 100% |
| Boot Volumes | 150 GB (50 GB x 3) | 200 GB | 75% |
| VCN | 1 | 2 | 50% |
| NLB | 1 | 1 | 100% |
| AMD Micro instances | 0 | 2 | Available |

## Traffic Flow

1. Client sends HTTPS request to NLB's reserved public IP
2. NLB forwards TCP 443 to Control Plane node (Ingress Controller)
3. Ingress Controller terminates TLS (via cert-manager + Let's Encrypt)
4. Request is routed to the appropriate Pod (on any of the 3 nodes)
5. Node-to-node communication uses private IPs within the VCN

## Security

- **Inbound** restricted to ports 22 (SSH), 80 (HTTP), 443 (HTTPS)
- **VCN internal** traffic fully open for K8s inter-node communication
- **Outbound** fully open via Internet Gateway
- **SSH access** via OCI Bastion Service (temporary sessions, max 3 hours)

## Files

| File | Description |
|------|-------------|
| `provider.tf` | OCI provider and version constraints |
| `variables.tf` | Input variables (tenancy OCID, SSH key, compute specs) |
| `locals.tf` | Shared values (compartment ID, CIDR blocks) |
| `data.tf` | Dynamic lookup for Ubuntu 24.04 Arm image |
| `network.tf` | VCN, Internet Gateway, route table, subnet |
| `security.tf` | Security list (inbound/outbound rules) |
| `compute.tf` | 3x A1.Flex instances (1 control plane + 2 workers) |
| `loadbalancer.tf` | NLB with reserved IP, TCP 80/443 listeners |
| `bastion.tf` | OCI Bastion Service |
| `outputs.tf` | Public/private IPs, NLB IP, bastion OCID |

## Usage

```bash
cp terraform.tfvars.example terraform.tfvars
# Edit terraform.tfvars with your values

terraform init
terraform plan
terraform apply
```

## Post-Provisioning (Manual)

1. SSH to control plane via Bastion or public IP
2. Install kubeadm, kubelet, kubectl on all 3 nodes
3. `kubeadm init` on control plane (remove default taint to allow workloads)
4. `kubeadm join` on both workers
5. Install Nginx Ingress Controller
6. Install cert-manager + Let's Encrypt ClusterIssuer
7. Point your domain DNS to NLB public IP
