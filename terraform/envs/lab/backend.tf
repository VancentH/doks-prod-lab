terraform {
  backend "s3" {
    bucket = "dpl-example"
    key    = "lab/terraform.tfstate"
    region = "us-east-1"

    endpoints = {
      s3 = "https://sgp1.digitaloceanspaces.com"
      # Region of the state bucket, NOT of the cluster.
    }

    skip_credentials_validation = true
    skip_requesting_account_id  = true
    skip_metadata_api_check     = true
    skip_region_validation      = true
    skip_s3_checksum            = true
  }
}