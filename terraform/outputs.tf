# ──────────────────────────────────────────────
# Network
# ──────────────────────────────────────────────

output "vcn_id" {
  description = "VCN OCID"
  value       = oci_core_vcn.k8s.id
}

output "ingress_public_ip" {
  description = "Reserved public IP for K8s ingress (attached to control plane)"
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

# ──────────────────────────────────────────────
# Storage
# ──────────────────────────────────────────────

output "workspace_volume_id" {
  description = "Block Volume OCID for control plane workspace"
  value       = oci_core_volume.workspace.id
}

# ──────────────────────────────────────────────
# Monitoring
# ──────────────────────────────────────────────

output "objectstorage_namespace" {
  description = "OCI Object Storage namespace (needed for Loki S3 config)"
  value       = data.oci_objectstorage_namespace.ns.namespace
}

output "loki_bucket_name" {
  description = "Loki Object Storage bucket name"
  value       = oci_objectstorage_bucket.loki.name
}

# ──────────────────────────────────────────────
# MySQL
# ──────────────────────────────────────────────

output "mysql_admin_password" {
  description = "MySQL admin password"
  value       = var.mysql_admin_password
  sensitive   = true
}

output "mysql_private_ip" {
  description = "Private IP of MySQL HeatWave DB System"
  value       = oci_mysql_mysql_db_system.vaultwarden.ip_address
}

output "mysql_port" {
  description = "MySQL port"
  value       = oci_mysql_mysql_db_system.vaultwarden.port
}
