terraform {
  required_providers {
    oci = {
      source  = "oracle/oci"
      version = ">= 5.0.0"
    }
  }

  # OCI Object Storage speaks the S3 API, so the stock s3 backend works — but
  # every AWS-specific side quest has to be switched off explicitly. Credentials
  # come from the `[oci]` profile in ~/.aws/credentials, so every command needs
  # AWS_PROFILE=oci (see docs/reference/index.md).
  backend "s3" {
    bucket = "tfstate-oracle-cloud"
    key    = "terraform.tfstate"
    region = "ap-singapore-1"

    # Terraform >= 1.6 renamed these: `endpoint` -> `endpoints.s3`,
    # `force_path_style` -> `use_path_style`. The old spellings still worked but
    # warned; they are kept current here so the warning noise doesn't mask a
    # real error later.
    endpoints = {
      s3 = "https://axhmpfnlwpld.compat.objectstorage.ap-singapore-1.oraclecloud.com"
    }
    use_path_style = true

    skip_region_validation      = true
    skip_credentials_validation = true
    skip_metadata_api_check     = true

    # Without this, the backend tries to resolve the AWS account ID via STS and
    # then iam:ListRoles. Neither exists on OCI, so init fails outright with
    # "AWS account ID not previously found" — not a credentials problem, which
    # is what the message reads like.
    skip_requesting_account_id = true

    # OCI Object Storage rejects aws-sdk-go v2's checksummed / aws-chunked
    # uploads with HTTP 501 (the same incompatibility that crash-looped Loki
    # 3.7+ until AWS_REQUEST_CHECKSUM_CALCULATION=when_required was set).
    # Terraform >= 1.6 uses that SDK, so state *writes* would hit it on apply
    # even though plan, being read-only, looks fine.
    skip_s3_checksum = true
  }
}

provider "oci" {
  region = var.region
}
