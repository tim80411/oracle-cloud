# ──────────────────────────────────────────────
# Provider & Tenancy
# ──────────────────────────────────────────────

variable "tenancy_ocid" {
  description = "OCID of the tenancy (compartment for Always Free)"
  type        = string
}

variable "region" {
  description = "OCI home region"
  type        = string
  default     = "ap-singapore-1"
}

# ──────────────────────────────────────────────
# Compute
# ──────────────────────────────────────────────

variable "ssh_public_key" {
  description = "SSH public key for instance access"
  type        = string
}

variable "control_plane_ocpus" {
  description = "OCPUs for K8s control plane node"
  type        = number
  default     = 2
}

variable "control_plane_memory_gb" {
  description = "Memory (GB) for K8s control plane node"
  type        = number
  default     = 8
}

variable "worker_ocpus" {
  description = "OCPUs for each K8s worker node"
  type        = number
  default     = 1
}

variable "worker_memory_gb" {
  description = "Memory (GB) for each K8s worker node"
  type        = number
  default     = 8
}

variable "worker_count" {
  description = "Number of K8s worker nodes"
  type        = number
  default     = 2
}

variable "boot_volume_size_gb" {
  description = "Boot volume size in GB per instance"
  type        = number
  default     = 50
}

# ──────────────────────────────────────────────
# Storage
# ──────────────────────────────────────────────

variable "workspace_volume_size_gb" {
  description = "Block volume size in GB for control plane workspace"
  type        = number
  default     = 50
}
