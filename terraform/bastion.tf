# ──────────────────────────────────────────────
# OCI Bastion Service (SSH jump to K8s nodes)
# ──────────────────────────────────────────────

resource "oci_bastion_bastion" "k8s" {
  compartment_id               = local.compartment_id
  bastion_type                 = "STANDARD"
  name                         = "k8s-bastion"
  target_subnet_id             = oci_core_subnet.public.id
  client_cidr_block_allow_list = ["0.0.0.0/0"]
  max_session_ttl_in_seconds   = 10800 # 3 hours
}
