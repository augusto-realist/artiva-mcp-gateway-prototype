resource "google_service_account" "gateway" {
  project      = var.project_id
  account_id   = "artiva-mcp-gateway"
  display_name = "Artiva MCP gateway (sandbox, Cloud Run)"
}

# Sandbox-only, temporary: lets the AUTH_MODE=local test run on Cloud Run and
# query BigQuery as this service account, before Okta/WIF exist to provide a
# per-user token. This is NOT part of the real design -- once AUTH_MODE=okta
# is in use, queries run as the federated user's own token instead, and this
# service account only needs to exist (to run the container), not hold any
# BigQuery role itself. Don't carry these two bindings into the real Artiva
# deployment.
resource "google_project_iam_member" "gateway_bq_viewer" {
  project = var.project_id
  role    = "roles/bigquery.dataViewer"
  member  = "serviceAccount:${google_service_account.gateway.email}"
}

resource "google_project_iam_member" "gateway_bq_job_user" {
  project = var.project_id
  role    = "roles/bigquery.jobUser"
  member  = "serviceAccount:${google_service_account.gateway.email}"
}
