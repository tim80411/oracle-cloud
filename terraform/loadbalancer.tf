# ──────────────────────────────────────────────
# Reserved Public IP
# ──────────────────────────────────────────────

resource "oci_core_public_ip" "nlb" {
  compartment_id = local.compartment_id
  lifetime       = "RESERVED"
  display_name   = "k8s-nlb-public-ip"
}

# ──────────────────────────────────────────────
# Network Load Balancer
# ──────────────────────────────────────────────

resource "oci_network_load_balancer_network_load_balancer" "k8s" {
  compartment_id = local.compartment_id
  display_name   = "k8s-nlb"
  subnet_id      = oci_core_subnet.public.id
  is_private     = false

  reserved_ips {
    id = oci_core_public_ip.nlb.id
  }
}

# ──────────────────────────────────────────────
# Backend Set (points to Control Plane)
# ──────────────────────────────────────────────

resource "oci_network_load_balancer_backend_set" "ingress" {
  network_load_balancer_id = oci_network_load_balancer_network_load_balancer.k8s.id
  name                     = "k8s-ingress-backend-set"
  policy                   = "FIVE_TUPLE"

  health_checker {
    protocol           = "TCP"
    port               = 80
    interval_in_millis = 10000
    timeout_in_millis  = 3000
    retries            = 3
  }
}

# Backend: Control Plane node (runs Ingress Controller)
resource "oci_network_load_balancer_backend" "control_plane_http" {
  network_load_balancer_id = oci_network_load_balancer_network_load_balancer.k8s.id
  backend_set_name         = oci_network_load_balancer_backend_set.ingress.name
  port                     = 80
  target_id                = oci_core_instance.control_plane.id
}

# ──────────────────────────────────────────────
# Backend Set for HTTPS
# ──────────────────────────────────────────────

resource "oci_network_load_balancer_backend_set" "ingress_https" {
  network_load_balancer_id = oci_network_load_balancer_network_load_balancer.k8s.id
  name                     = "k8s-ingress-https-backend-set"
  policy                   = "FIVE_TUPLE"

  health_checker {
    protocol           = "TCP"
    port               = 443
    interval_in_millis = 10000
    timeout_in_millis  = 3000
    retries            = 3
  }
}

resource "oci_network_load_balancer_backend" "control_plane_https" {
  network_load_balancer_id = oci_network_load_balancer_network_load_balancer.k8s.id
  backend_set_name         = oci_network_load_balancer_backend_set.ingress_https.name
  port                     = 443
  target_id                = oci_core_instance.control_plane.id
}

# ──────────────────────────────────────────────
# Listeners
# ──────────────────────────────────────────────

resource "oci_network_load_balancer_listener" "http" {
  network_load_balancer_id = oci_network_load_balancer_network_load_balancer.k8s.id
  name                     = "http-listener"
  default_backend_set_name = oci_network_load_balancer_backend_set.ingress.name
  port                     = 80
  protocol                 = "TCP"
}

resource "oci_network_load_balancer_listener" "https" {
  network_load_balancer_id = oci_network_load_balancer_network_load_balancer.k8s.id
  name                     = "https-listener"
  default_backend_set_name = oci_network_load_balancer_backend_set.ingress_https.name
  port                     = 443
  protocol                 = "TCP"
}
