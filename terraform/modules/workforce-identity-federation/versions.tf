# Not an upstream Cloud Foundation Fabric module -- project-authored, so
# deliberately no "# Fabric release:" comment or provider_meta block here
# (see main.tf's own comment for why).
terraform {
  required_version = ">= 1.10.2"
  required_providers {
    google = {
      source  = "hashicorp/google"
      version = ">= 6.19.0, < 7.0.0"
    }
  }
}
