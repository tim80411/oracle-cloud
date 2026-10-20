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

# 30 天沒動的散裝 jsonl 原地轉 Archive（物件名稱、大小、LastModified 都不變）。
# 上傳端是 `aws s3 sync`，只比對大小與修改時間，所以原地改層不會被補傳回來；
# 2026-10-20 已拿單一物件實測 update-storage-tier + sync --dryrun，確認沒有重傳。
# 取代 2026-08-16 手動打包 tar.zst 的做法（打包後刪散檔，本機還在的檔案會被 sync 傳回來）。
# 代價：Archive 物件要先 restore（約 1 小時）才能讀，且最少計費 90 天。
resource "oci_objectstorage_object_lifecycle_policy" "claude_code_jsonl" {
  namespace = data.oci_objectstorage_namespace.ns.namespace
  bucket    = oci_objectstorage_bucket.claude_code_jsonl.name

  rules {
    name        = "archive-jsonl-after-30d"
    action      = "ARCHIVE"
    time_amount = 30
    time_unit   = "DAYS"
    is_enabled  = true
    target      = "objects"

    object_name_filter {
      inclusion_prefixes = ["projects/"]
    }
  }

  depends_on = [oci_identity_policy.objectstorage_lifecycle]
}

# Lifecycle 規則由 Object Storage 服務本身代為搬移物件，需要明確授權。
resource "oci_identity_policy" "objectstorage_lifecycle" {
  compartment_id = var.tenancy_ocid
  name           = "objectstorage-lifecycle-claude-code-jsonl"
  description    = "Let Object Storage lifecycle rules archive objects in claude-code-jsonl"
  statements = [
    "Allow service objectstorage-${var.region} to manage object-family in tenancy where target.bucket.name = '${oci_objectstorage_bucket.claude_code_jsonl.name}'",
  ]
}
