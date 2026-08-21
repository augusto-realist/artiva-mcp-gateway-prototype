# tfdoc:file:description The deployed service and everything it needs to exist and run: image storage, the running container, secrets, and Cloud Build permission.

# Closes a real gotcha hit during Phase B: newer GCP projects don't
# auto-grant the Compute Engine default service account permission to run
# Cloud Build, so the first `gcloud builds submit` on a fresh project fails
# until this is granted by hand.
resource "google_project_service" "cloud_build" {
  project            = var.project_id
  service            = "cloudbuild.googleapis.com"
  disable_on_destroy = false
}

data "google_project" "current" {
  project_id = var.project_id
}

resource "google_project_iam_member" "compute_default_sa_cloud_build_builder" {
  project = var.project_id
  role    = "roles/cloudbuild.builds.builder"
  member  = "serviceAccount:${data.google_project.current.number}-compute@developer.gserviceaccount.com"
}

module "images" {
  source = "./modules/artifact-registry"

  project_id  = var.project_id
  location    = var.region
  name        = "artiva-mcp-gateway"
  description = "Container images for the Artiva MCP gateway prototype (sandbox)."
  format = {
    docker = { standard = {} }
  }

  depends_on = [google_project_service.artifact_registry]
}

# OKTA_CLIENT_SECRET's container -- only needed for AUTH_MODE=okta_broker.
# Deliberately does not create a version/value through this module's
# `versions` variable -- the real secret string is added out-of-band
# (`gcloud secrets versions add`), so it never touches terraform.tfstate.
module "secrets" {
  source = "./modules/secret-manager"

  project_id = var.project_id
  secrets = {
    "okta-client-secret" = {}
  }
  iam = {
    "okta-client-secret" = {
      "roles/secretmanager.secretAccessor" = ["serviceAccount:${google_service_account.gateway.email}"]
    }
  }

  depends_on = [google_project_service.secret_manager]
}

module "gateway" {
  source = "./modules/cloud-run-v2"

  project_id = var.project_id
  region     = var.region
  name       = "artiva-mcp-gateway"

  # Plain variables at this Fabric release (v37.2.0), not a nested
  # service_config/service_account_config object -- confirmed directly
  # against the vendored module's own variables.tf before writing this,
  # since a newer (master-branch) release of this same module uses a
  # different, nested shape.
  service_account        = google_service_account.gateway.email
  service_account_create = false
  ingress                = "INGRESS_TRAFFIC_ALL"

  revision = {
    min_instance_count = 0
  }

  # Stays allUsers even under AUTH_MODE=okta/okta_broker -- Claude reaches
  # this endpoint as an anonymous HTTP client (it has no Google-recognized
  # identity of its own), so restricting Cloud Run's own invoker IAM would
  # block Claude entirely regardless of auth mode. Once past AUTH_MODE=local,
  # the real gate moves to the application layer instead (OktaTokenVerifier /
  # the broker's own token validation rejects unauthenticated requests).
  # Under AUTH_MODE=local specifically (no application-layer auth either)
  # this is still a genuinely open door, acceptable only because the data is
  # disposable sandbox rows -- never carry AUTH_MODE=local + allUsers into
  # the real deployment.
  iam = {
    "roles/run.invoker" = ["allUsers"]
  }

  containers = {
    gateway = {
      image = var.image
      env = {
        AUTH_MODE                 = var.auth_mode
        BQ_PROJECT_ID              = var.project_id
        OKTA_ISSUER                = var.okta_issuer
        OKTA_CLIENT_ID             = var.okta_client_id
        OKTA_GROUPS_CLAIM          = "groups"
        GCP_WORKFORCE_POOL_ID      = module.workforce_identity.pool_id
        GCP_WORKFORCE_PROVIDER_ID  = module.workforce_identity.provider_id
        GCP_BILLING_PROJECT        = var.project_id
        PUBLIC_URL                 = var.gateway_public_url
      }
      # Only needed for okta_broker (the only mode that talks to Okta's
      # /token endpoint itself) -- sourced from Secret Manager, so the real
      # value is never a Terraform variable/plan output and never appears
      # as a plain Cloud Run env var value; Cloud Run resolves it at
      # container-start time instead.
      env_from_key = var.auth_mode == "okta_broker" ? {
        OKTA_CLIENT_SECRET = {
          secret  = "okta-client-secret"
          version = "latest"
        }
      } : {}
    }
  }

  depends_on = [
    google_project_service.run,
    module.secrets,
  ]
}
