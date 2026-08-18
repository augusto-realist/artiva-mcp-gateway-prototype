resource "google_cloud_run_v2_service" "gateway" {
  project  = var.project_id
  name     = "artiva-mcp-gateway"
  location = var.region
  ingress  = "INGRESS_TRAFFIC_ALL"

  template {
    service_account = google_service_account.gateway.email

    containers {
      image = var.image

      env {
        name  = "AUTH_MODE"
        value = "local"
      }
      env {
        name  = "BQ_PROJECT_ID"
        value = var.project_id
      }
    }
  }

  depends_on = [google_project_service.run]
}

# Sandbox-only, temporary: allows unauthenticated invocation so the MCP
# client smoke test can hit the URL directly without also standing up
# identity-token plumbing for the test itself. AUTH_MODE=local has no
# authentication of its own either, so this Cloud Run service is, for now,
# a genuinely open door to the sandbox project's BigQuery data -- acceptable
# only because that data is disposable test rows in a throwaway project.
# Revisit before Phase D (Okta) and never carry this into the real
# deployment, where Claude's own connector auth plus AUTH_MODE=okta replace
# the need for this entirely.
resource "google_cloud_run_v2_service_iam_member" "public_invoker" {
  project  = google_cloud_run_v2_service.gateway.project
  location = google_cloud_run_v2_service.gateway.location
  name     = google_cloud_run_v2_service.gateway.name
  role     = "roles/run.invoker"
  member   = "allUsers"
}
