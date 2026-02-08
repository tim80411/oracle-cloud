# Latest Ubuntu 24.04 Arm image
data "oci_core_images" "ubuntu_arm" {
  compartment_id           = local.compartment_id
  operating_system         = "Canonical Ubuntu"
  operating_system_version = "24.04"
  shape                    = "VM.Standard.A1.Flex"
  sort_by                  = "TIMECREATED"
  sort_order               = "DESC"
}

# Availability domain
data "oci_identity_availability_domains" "ads" {
  compartment_id = var.tenancy_ocid
}
