# tfdoc:file:description Gateway service account and the Okta <-> Google Workforce Identity Federation trust.

resource "google_service_account" "gateway" {
  project      = var.project_id
  account_id   = "artiva-mcp-gateway"
  display_name = "Artiva MCP gateway (sandbox, Cloud Run)"
}

# Sandbox-only, temporary: lets the AUTH_MODE=local test run on Cloud Run and
# query BigQuery as this service account, before Okta/WIF exist to provide a
# per-user token. This is NOT part of the real design -- once AUTH_MODE=okta
# (or okta_broker) is in use, queries run as the federated user's own token
# instead, and this service account only needs to exist (to run the
# container), not hold any BigQuery role itself. Don't carry these two
# bindings into the real Artiva deployment.
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

# Originally created by hand via `gcloud iam workforce-pools create` /
# `providers create-oidc` during Phase D (see
# Notes/GCP Sandbox/Commands Run - Sandbox Setup.md and History/STATUS.md's
# Phase D section for why several of the module's defaults were needed --
# e.g. the web_sso_config block was required by the installed gcloud CLI
# even though it's conceptually unused by this gateway's pure backend
# token-exchange flow). Brought under Terraform via `terraform import` (not
# `apply`) -- this provider took three separate, unrelated rounds of
# troubleshooting to get working (a missing Google-console redirect URI
# registered on the Okta side, a bogus `groups` OAuth scope request, and
# Okta's default Authorization Server missing its Access Policy). None of
# that Okta-side config is visible or managed here -- only the GCP-side
# trust configuration is. Do not `terraform destroy` this without expecting
# to redo that Okta-side setup too.
module "workforce_identity" {
  source = "./modules/workforce-identity-federation"

  pool_id         = var.wif_pool_id
  pool_parent     = var.wif_pool_parent
  provider_id     = var.wif_provider_id
  display_name    = "Artiva MCP Sandbox"
  description     = "Sandbox workforce pool for testing Okta-federated BigQuery access via the MCP gateway prototype"
  provider_display_name = "Okta (sandbox)"
  provider_description   = "Okta Integrator Free Plan trial, custom authorization server 'default'"
  okta_issuer     = var.okta_issuer
  okta_client_id  = var.okta_client_id
}
