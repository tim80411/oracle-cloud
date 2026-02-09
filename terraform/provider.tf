terraform {
  required_providers {
    oci = {
      source  = "oracle/oci"
      version = ">= 5.0.0"
    }
  }

  # Pre-requisite: run `terraform apply` in bootstrap/ first to create the bucket.
  # Then fill in the endpoint from bootstrap output and run `terraform init`.
  #
  # backend "s3" {
  #   bucket                      = "tfstate-oracle-cloud"
  #   key                         = "terraform.tfstate"
  #   region                      = "ap-singapore-1"
  #   endpoint                    = "https://<namespace>.compat.objectstorage.ap-singapore-1.oraclecloud.com"
  #   skip_region_validation      = true
  #   skip_credentials_validation = true
  #   skip_metadata_api_check     = true
  #   force_path_style            = true
  # }
}

provider "oci" {
  region = var.region
}
