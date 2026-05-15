# ──────────────────────────────────────────────
# Backups – k8up Object Storage + dedicated IAM user
# ──────────────────────────────────────────────
#
# Target consumer: k8up backup operator running in the K8s cluster.
#
# Uses a dedicated IAM user so the Customer Secret Key
# counts against this user's quota (not the tenancy admin's
# already-saturated 2-key limit) and can be revoked
# independently of other service credentials.

resource "oci_objectstorage_bucket" "k8up_backups" {
  compartment_id = local.compartment_id
  namespace      = data.oci_objectstorage_namespace.ns.namespace
  name           = "k8up-backups"
  access_type    = "NoPublicAccess"
  versioning     = "Disabled"
}

resource "oci_identity_user" "k8up_backup" {
  compartment_id = var.tenancy_ocid
  name           = "k8up-backup"
  description    = "Service user for k8up backup operator (S3-compat access to k8up-backups bucket)"
  email          = var.k8up_backup_user_email
}

resource "oci_identity_group" "k8up_backup" {
  compartment_id = var.tenancy_ocid
  name           = "k8up-backup"
  description    = "Group granting bucket access to the k8up service user"
}

resource "oci_identity_user_group_membership" "k8up_backup" {
  user_id  = oci_identity_user.k8up_backup.id
  group_id = oci_identity_group.k8up_backup.id
}

resource "oci_identity_policy" "k8up_backup" {
  compartment_id = var.tenancy_ocid
  name           = "k8up-backup-bucket-access"
  description    = "Read/write objects in the k8up-backups bucket"
  statements = [
    "Allow group ${oci_identity_group.k8up_backup.name} to read buckets in tenancy where target.bucket.name = '${oci_objectstorage_bucket.k8up_backups.name}'",
    "Allow group ${oci_identity_group.k8up_backup.name} to manage objects in tenancy where target.bucket.name = '${oci_objectstorage_bucket.k8up_backups.name}'",
  ]
}

resource "oci_identity_customer_secret_key" "k8up" {
  user_id      = oci_identity_user.k8up_backup.id
  display_name = "k8up-backups"
}
