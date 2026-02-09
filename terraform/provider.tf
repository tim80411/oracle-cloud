terraform {
  required_providers {
    oci = {
      source  = "oracle/oci"
      version = ">= 5.0.0"
    }
  }

  backend "s3" {
    bucket                      = "tfstate-oracle-cloud"
    key                         = "terraform.tfstate"
    region                      = "ap-singapore-1"
    endpoint                    = "https://axhmpfnlwpld.compat.objectstorage.ap-singapore-1.oraclecloud.com"
    skip_region_validation      = true
    skip_credentials_validation = true
    skip_metadata_api_check     = true
    force_path_style            = true
  }
}

provider "oci" {
  region = var.region
}
