resource "google_cloud_run_v2_service" "gateway" {
  project  = var.project_id
  name     = "artiva-mcp-gateway"
  location = var.region
  ingress  = "INGRESS_TRAFFIC_ALL"

  # Declared explicitly (matching Cloud Run's own defaults: scale-to-zero,
  # automatic mode) to stop a perpetual diff -- the API always reports real
  # values for this block regardless of what's configured, and the
  # provider's schema treats these fields as plain Optional rather than
  # Optional+Computed, so an absent block gets re-populated from the API on
  # every refresh and then diffed away again on every plan.
  scaling {
    min_instance_count = 0
  }

  template {
    service_account = google_service_account.gateway.email

    containers {
      image = var.image

      env {
        name  = "AUTH_MODE"
        value = var.auth_mode
      }
      env {
        name  = "BQ_PROJECT_ID"
        value = var.project_id
      }
      env {
        name  = "OKTA_ISSUER"
        value = var.okta_issuer
      }
      env {
        name  = "OKTA_CLIENT_ID"
        value = var.okta_client_id
      }
      env {
        name  = "OKTA_GROUPS_CLAIM"
        value = "groups"
      }
      env {
        name  = "GCP_WORKFORCE_POOL_ID"
        value = var.wif_pool_id
      }
      env {
        name  = "GCP_WORKFORCE_PROVIDER_ID"
        value = var.wif_provider_id
      }
      env {
        name  = "GCP_BILLING_PROJECT"
        value = var.project_id
      }
      env {
        name  = "PUBLIC_URL"
        value = var.gateway_public_url
      }
    }
  }

  depends_on = [google_project_service.run]
}

# Stays allUsers even under AUTH_MODE=okta -- Claude reaches this endpoint
# as an anonymous HTTP client (it has no Google-recognized identity of its
# own), so restricting Cloud Run's own invoker IAM would block Claude
# entirely regardless of auth mode. Once AUTH_MODE=okta, the real gate moves
# to the application layer: OktaTokenVerifier rejects any request without a
# genuine, signature-verified Okta token. Under AUTH_MODE=local specifically
# (no application-layer auth either) this is still a genuinely open door,
# acceptable only because the data is disposable sandbox rows -- never carry
# AUTH_MODE=local + allUsers into the real deployment.
resource "google_cloud_run_v2_service_iam_member" "public_invoker" {
  project  = google_cloud_run_v2_service.gateway.project
  location = google_cloud_run_v2_service.gateway.location
  name     = google_cloud_run_v2_service.gateway.name
  role     = "roles/run.invoker"
  member   = "allUsers"
}
