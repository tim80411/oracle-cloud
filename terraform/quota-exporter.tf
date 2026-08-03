# ──────────────────────────────────────────────
# Quota exporter – Instance Principal auth
# ──────────────────────────────────────────────
#
# Target consumer: the `oci-quota-exporter` Deployment in the k8s-apps
# repo (apps/oci-quota-exporter). It polls three OCI APIs and republishes
# the answers as Prometheus gauges so Grafana can show how much Always
# Free headroom is left:
#
#   Usage API   -> accrued monthly quantities (egress, request counts,
#                  OCPU-hours). Authoritative: billing semantics, and the
#                  units already match the published Free quotas.
#   Limits API  -> point-in-time allocation, plus `total-free-storage-gb`,
#                  the one field that is natively Free-tier aware.
#   Monitoring  -> per-bucket Object Storage split, which neither of the
#                  other two can produce.
#
# Instance Principal rather than an API key: the cluster nodes are
# themselves OCI instances, so they can sign API requests with their own
# identity. Nothing to seal into git, nothing to rotate.
#
# Scope note: the matching rule covers every instance in the compartment
# instead of pinning instance OCIDs. Always Free nodes get rebuilt and
# come back with new OCIDs, so a pinned list would silently stop working
# — the failure mode being an exporter that quietly returns nothing.
# Every instance in this compartment is a cluster node and every granted
# permission is read-only, so the blast radius is "any pod on any node
# can read quota numbers".

resource "oci_identity_dynamic_group" "quota_exporter" {
  compartment_id = var.tenancy_ocid
  name           = "quota-exporter-instances"
  description    = "Cluster nodes permitted to read Always Free quota usage via instance principal"
  matching_rule  = "ALL {instance.compartment.id = '${local.compartment_id}'}"
}

resource "oci_identity_policy" "quota_exporter" {
  compartment_id = var.tenancy_ocid
  name           = "quota-exporter-read"
  description    = "Read-only usage, limits and metrics access for the Always Free quota dashboard"

  statements = [
    # Usage API (RequestSummarizedUsages) with --query-type USAGE. Always Free
    # resources bill at $0 but still record a non-zero `computed-quantity`,
    # which is exactly what the dashboard needs.
    "Allow dynamic-group ${oci_identity_dynamic_group.quota_exporter.name} to read usage-reports in tenancy",

    # Limits API. ListServices / ListLimitDefinitions / ListLimitValues need
    # `inspect`; GetResourceAvailability needs `read`. Note the resource-type
    # token is `resource-availability` — NOT `limits`, which is a different
    # (and insufficient) token that only covers ListLimitValues.
    "Allow dynamic-group ${oci_identity_dynamic_group.quota_exporter.name} to inspect resource-availability in tenancy",
    "Allow dynamic-group ${oci_identity_dynamic_group.quota_exporter.name} to read resource-availability in tenancy",

    # Monitoring (SummarizeMetricsData) for oci_objectstorage/StoredBytes per
    # bucket and oci_internet_gateway/BytesToIgw. Use the IGW metric for egress,
    # never oci_vcn/VnicToNetworkBytes — the latter counts intra-cluster traffic
    # and overstates real egress by ~4x.
    "Allow dynamic-group ${oci_identity_dynamic_group.quota_exporter.name} to read metrics in tenancy",
  ]
}

output "quota_exporter_dynamic_group" {
  description = "Dynamic group backing the quota exporter's instance-principal auth."
  value       = oci_identity_dynamic_group.quota_exporter.name
}
