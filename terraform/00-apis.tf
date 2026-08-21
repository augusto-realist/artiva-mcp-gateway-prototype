# tfdoc:file:description API enablement.

resource "google_project_service" "run" {
  project            = var.project_id
  service            = "run.googleapis.com"
  disable_on_destroy = false
}

resource "google_project_service" "artifact_registry" {
  project            = var.project_id
  service            = "artifactregistry.googleapis.com"
  disable_on_destroy = false
}

# Originally enabled manually during initial sandbox setup, before this
# Terraform config existed. Managed here now so a from-scratch `terraform
# apply` against a fresh project doesn't silently depend on that one-off
# manual step -- without it, `terraform apply` would still succeed, but the
# app would fail at runtime with a BigQuery "API not enabled" error.
resource "google_project_service" "bigquery" {
  project            = var.project_id
  service            = "bigquery.googleapis.com"
  disable_on_destroy = false
}

resource "google_project_service" "secret_manager" {
  project            = var.project_id
  service            = "secretmanager.googleapis.com"
  disable_on_destroy = false
}
