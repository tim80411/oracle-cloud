# ──────────────────────────────────────────────
# Security List (K8s nodes — public subnet)
# ──────────────────────────────────────────────

resource "oci_core_security_list" "k8s" {
  compartment_id = local.compartment_id
  vcn_id         = oci_core_vcn.k8s.id
  display_name   = "k8s-security-list"

  # ── Ingress ──

  # Allow all traffic within VCN (node-to-node K8s communication)
  ingress_security_rules {
    protocol    = "all"
    source      = local.vcn_cidr
    source_type = "CIDR_BLOCK"
    stateless   = false
  }

  # Allow HTTP from internet (NLB health checks + traffic)
  ingress_security_rules {
    protocol    = "6" # TCP
    source      = "0.0.0.0/0"
    source_type = "CIDR_BLOCK"
    stateless   = false
    tcp_options {
      min = 80
      max = 80
    }
  }

  # Allow HTTPS from internet
  ingress_security_rules {
    protocol    = "6"
    source      = "0.0.0.0/0"
    source_type = "CIDR_BLOCK"
    stateless   = false
    tcp_options {
      min = 443
      max = 443
    }
  }

  # Allow SSH (for Bastion Service or direct access)
  ingress_security_rules {
    protocol    = "6"
    source      = "0.0.0.0/0"
    source_type = "CIDR_BLOCK"
    stateless   = false
    tcp_options {
      min = 22
      max = 22
    }
  }

  # ── Egress ──

  # Allow all outbound
  egress_security_rules {
    protocol         = "all"
    destination      = "0.0.0.0/0"
    destination_type = "CIDR_BLOCK"
    stateless        = false
  }
}
