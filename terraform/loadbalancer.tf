# ──────────────────────────────────────────────
# Reserved Public IP → Control Plane Node
# ──────────────────────────────────────────────

resource "oci_core_public_ip" "nlb" {
  compartment_id = local.compartment_id
  lifetime       = "RESERVED"
  display_name   = "k8s-ingress-public-ip"
  private_ip_id  = data.oci_core_private_ips.control_plane.private_ips[0].id
}
