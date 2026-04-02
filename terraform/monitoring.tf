# ──────────────────────────────────────────────
# Monitoring – Loki Object Storage
# ──────────────────────────────────────────────

data "oci_objectstorage_namespace" "ns" {
  compartment_id = local.compartment_id
}

resource "oci_objectstorage_bucket" "loki" {
  compartment_id = local.compartment_id
  namespace      = data.oci_objectstorage_namespace.ns.namespace
  name           = "loki-chunks"
  access_type    = "NoPublicAccess"
}

# ──────────────────────────────────────────────
# Monitoring – Claude Code JSONL Storage
# ──────────────────────────────────────────────

resource "oci_objectstorage_bucket" "claude_code_jsonl" {
  compartment_id = local.compartment_id
  namespace      = data.oci_objectstorage_namespace.ns.namespace
  name           = "claude-code-jsonl"
  access_type    = "NoPublicAccess"
}
