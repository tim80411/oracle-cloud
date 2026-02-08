locals {
  compartment_id = var.tenancy_ocid

  vcn_cidr           = "10.0.0.0/16"
  public_subnet_cidr = "10.0.0.0/24"
}
