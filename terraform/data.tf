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

# Control plane VNIC (for reserved IP assignment)
data "oci_core_vnic_attachments" "control_plane" {
  compartment_id = local.compartment_id
  instance_id    = oci_core_instance.control_plane.id
}

data "oci_core_vnic" "control_plane" {
  vnic_id = data.oci_core_vnic_attachments.control_plane.vnic_attachments[0].vnic_id
}

data "oci_core_private_ips" "control_plane" {
  vnic_id = data.oci_core_vnic.control_plane.id
}
