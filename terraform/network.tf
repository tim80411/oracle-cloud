# ──────────────────────────────────────────────
# VCN
# ──────────────────────────────────────────────

resource "oci_core_vcn" "k8s" {
  compartment_id = local.compartment_id
  cidr_blocks    = [local.vcn_cidr]
  display_name   = "k8s-vcn"
  dns_label      = "k8svcn"
}

# ──────────────────────────────────────────────
# Gateways
# ──────────────────────────────────────────────

resource "oci_core_internet_gateway" "igw" {
  compartment_id = local.compartment_id
  vcn_id         = oci_core_vcn.k8s.id
  display_name   = "k8s-internet-gateway"
  enabled        = true
}

# ──────────────────────────────────────────────
# Route Table
# ──────────────────────────────────────────────

resource "oci_core_route_table" "public" {
  compartment_id = local.compartment_id
  vcn_id         = oci_core_vcn.k8s.id
  display_name   = "public-route-table"

  route_rules {
    destination       = "0.0.0.0/0"
    destination_type  = "CIDR_BLOCK"
    network_entity_id = oci_core_internet_gateway.igw.id
  }
}

# ──────────────────────────────────────────────
# Subnet (all nodes in public subnet)
# ──────────────────────────────────────────────

resource "oci_core_subnet" "public" {
  compartment_id             = local.compartment_id
  vcn_id                     = oci_core_vcn.k8s.id
  cidr_block                 = local.public_subnet_cidr
  display_name               = "k8s-subnet"
  dns_label                  = "k8s"
  route_table_id             = oci_core_route_table.public.id
  security_list_ids          = [oci_core_security_list.k8s.id]
  prohibit_public_ip_on_vnic = false
  prohibit_internet_ingress  = false
}

# ──────────────────────────────────────────────
# Route Table (private — no internet gateway)
# ──────────────────────────────────────────────

resource "oci_core_route_table" "private" {
  compartment_id = local.compartment_id
  vcn_id         = oci_core_vcn.k8s.id
  display_name   = "private-route-table"
}

# ──────────────────────────────────────────────
# Private Subnet (MySQL)
# ──────────────────────────────────────────────

resource "oci_core_subnet" "private" {
  compartment_id             = local.compartment_id
  vcn_id                     = oci_core_vcn.k8s.id
  cidr_block                 = local.private_subnet_cidr
  display_name               = "mysql-subnet"
  dns_label                  = "mysql"
  route_table_id             = oci_core_route_table.private.id
  security_list_ids          = [oci_core_security_list.mysql.id]
  prohibit_public_ip_on_vnic = true
  prohibit_internet_ingress  = true
}
