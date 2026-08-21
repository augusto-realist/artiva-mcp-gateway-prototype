# The Okta OIDC app's client secret -- the one real secret this project
# handles (OKTA_CLIENT_ID is a public identifier, not a secret; see
# variables.tf). Only Terraform-manages the secret CONTAINER, deliberately
# not a version/value -- the actual secret string is added out-of-band
# (`gcloud secrets versions add`), so it never touches terraform.tfstate.
# Referenced natively from cloud_run.tf's env block via secret_key_ref,
# rather than passed through as a plain Terraform variable/env var value --
# see the previous approach's own comment history for why that wasn't
# sufficient (still ends up as plaintext on the live Cloud Run revision and
# in tfstate).
resource "google_secret_manager_secret" "okta_client_secret" {
  project   = var.project_id
  secret_id = "okta-client-secret"

  replication {
    auto {}
  }

  depends_on = [google_project_service.secret_manager]
}

resource "google_secret_manager_secret_iam_member" "gateway_secret_accessor" {
  project   = var.project_id
  secret_id = google_secret_manager_secret.okta_client_secret.secret_id
  role      = "roles/secretmanager.secretAccessor"
  member    = "serviceAccount:${google_service_account.gateway.email}"
}
