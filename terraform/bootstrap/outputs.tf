output "bucket_name" {
  value = oci_objectstorage_bucket.tfstate.name
}

output "namespace" {
  description = "Use this in the main backend config endpoint"
  value       = data.oci_objectstorage_namespace.ns.namespace
}

output "backend_endpoint" {
  description = "S3-compatible endpoint for main terraform backend"
  value       = "https://${data.oci_objectstorage_namespace.ns.namespace}.compat.objectstorage.${var.region}.oraclecloud.com"
}
