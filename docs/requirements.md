# Infrastructure Requirements

## Architecture Overview

```
Internet
    |
    v
+---------------------------+
|  Network Load Balancer    |  Reserved Public IP
|  (Layer 4, TCP 443/80)   |  No bandwidth limit
+------------+--------------+
             | Private IP
             v
+---------------------------+
|  K8s Control Plane        |  VM.Standard.A1.Flex (Arm)
|  + Ingress Controller     |  2 OCPU + 12 GB RAM
|  (HTTPS/TLS termination)  |  Also schedulable for workloads
+-----+------------+--------+
      |            |
      v            v
+------------+ +------------+
| Worker 1   | | Worker 2   |  VM.Standard.A1.Flex (Arm)
| 1 OCPU     | | 1 OCPU     |  1 OCPU + 6 GB RAM each
| 6 GB RAM   | | 6 GB RAM   |
+------------+ +------------+
```

## Compute Resource Allocation

| Role | Shape | OCPU | RAM | Notes |
|------|-------|------|-----|-------|
| K8s Control Plane | VM.Standard.A1.Flex | 2 | 12 GB | Runs Ingress Controller; also accepts workload Pods |
| K8s Worker 1 | VM.Standard.A1.Flex | 1 | 6 GB | General workloads |
| K8s Worker 2 | VM.Standard.A1.Flex | 1 | 6 GB | General workloads |
| **Total (Arm)** | | **4** | **24 GB** | **Matches Always Free limit** |

> AMD Micro instances (2x) are not used in this plan and remain available for other purposes (e.g., bastion host, monitoring).

## Networking Requirements

- **1 VCN** with public and private subnets
- **1 Network Load Balancer** with reserved public IP
  - TCP 443 listener -> Control Plane Ingress Controller
  - TCP 80 listener -> Control Plane Ingress Controller (HTTP redirect)
- **Internet Gateway** for outbound access
- **Security Lists / NSGs** to restrict traffic

## Kubernetes

- Full Kubernetes (kubeadm) on Arm (aarch64)
- Control Plane node also schedulable (remove default taint)
- Ingress Controller (e.g., Nginx) handles TLS termination
- Internal node-to-node communication via private IPs (HTTP)
- cert-manager + Let's Encrypt for automatic certificate management

## Storage Allocation

| Usage | Size | Notes |
|-------|------|-------|
| Control Plane boot volume | 50 GB | Default |
| Worker 1 boot volume | 50 GB | Default |
| Worker 2 boot volume | 50 GB | Default |
| **Total** | **150 GB** | **Within 200 GB Always Free limit; 50 GB remaining** |

## Design Decisions

1. **NLB over Flexible LB**: No 10 Mbps bandwidth limit; preserves client IP; sufficient for L4 forwarding
2. **2 Workers over 1**: Better fault tolerance (OCI idle reclaim risk); enables rolling updates
3. **Full K8s over K3s**: Learning full Kubernetes architecture (user preference)
4. **Control Plane also runs workloads**: Maximizes available resources in free tier
