# ──────────────────────────────────────────────
# MySQL HeatWave DB System (Always Free)
# ──────────────────────────────────────────────

resource "oci_mysql_mysql_db_system" "vaultwarden" {
  compartment_id      = local.compartment_id
  display_name        = "vaultwarden-mysql"
  shape_name          = "MySQL.Free"
  subnet_id           = oci_core_subnet.private.id
  availability_domain = data.oci_identity_availability_domains.ads.availability_domains[0].name

  admin_username = "admin"
  admin_password = var.mysql_admin_password

  data_storage_size_in_gb = 50

  lifecycle {
    prevent_destroy = true
  }
}
