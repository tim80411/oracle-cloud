# ──────────────────────────────────────────────
# Block Volume – Personal workspace on CP node
# ──────────────────────────────────────────────

resource "oci_core_volume" "workspace" {
  compartment_id      = local.compartment_id
  availability_domain = data.oci_identity_availability_domains.ads.availability_domains[0].name
  display_name        = "cp-workspace"
  size_in_gbs         = var.workspace_volume_size_gb
  vpus_per_gb         = 0

  lifecycle {
    prevent_destroy = true
  }
}

resource "oci_core_volume_attachment" "workspace" {
  attachment_type = "paravirtualized"
  instance_id     = oci_core_instance.control_plane.id
  volume_id       = oci_core_volume.workspace.id
  display_name    = "cp-workspace-attachment"
}
