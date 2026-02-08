# ──────────────────────────────────────────────
# Network
# ──────────────────────────────────────────────

output "vcn_id" {
  description = "VCN OCID"
  value       = oci_core_vcn.k8s.id
}

output "nlb_public_ip" {
  description = "Public IP of the Network Load Balancer"
  value       = oci_core_public_ip.nlb.ip_address
}

# ──────────────────────────────────────────────
# Compute
# ──────────────────────────────────────────────

output "control_plane_public_ip" {
  description = "Public IP of the K8s control plane node"
  value       = oci_core_instance.control_plane.public_ip
}

output "control_plane_private_ip" {
  description = "Private IP of the K8s control plane node"
  value       = oci_core_instance.control_plane.private_ip
}

output "worker_public_ips" {
  description = "Public IPs of K8s worker nodes"
  value       = oci_core_instance.worker[*].public_ip
}

output "worker_private_ips" {
  description = "Private IPs of K8s worker nodes"
  value       = oci_core_instance.worker[*].private_ip
}

# ──────────────────────────────────────────────
# Bastion
# ──────────────────────────────────────────────

output "bastion_id" {
  description = "Bastion OCID (use to create SSH sessions via OCI Console or CLI)"
  value       = oci_bastion_bastion.k8s.id
}
