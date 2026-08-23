terraform {
  required_version = ">= 1.10.2"

  required_providers {
    google = {
      source  = "hashicorp/google"
      # Tightened to match gcp-foundation-artiva's own pin, not the
      # previous ~> 6.0 -- the vendored Fabric modules under modules/ were
      # themselves pinned this way upstream.
      version = ">= 6.19.0, < 7.0.0"
    }
    google-beta = {
      source  = "hashicorp/google-beta"
      version = ">= 6.19.0, < 7.0.0"
    }
  }
}

provider "google" {
  project = var.project_id
  region  = var.region
}

# Several vendored Fabric modules (modules/cloud-run-v2,
# modules/artifact-registry, modules/secret-manager) use `provider =
# google-beta` internally for specific resources -- required even though
# nothing in this composition references google-beta directly.
provider "google-beta" {
  project = var.project_id
  region  = var.region
}
