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

# The original sandbox project already had this enabled by the time this
# Terraform started managing it -- never surfaced as a dependency until the
# fresh-project reproducibility test (2026-08-21) hit a real failure: the
# Compute Engine default service account
# ({project_number}-compute@developer.gserviceaccount.com, referenced in
# 03-run.tf's Cloud Build IAM grant) doesn't exist on a truly fresh project
# until this API is actually enabled -- it's not auto-provisioned at project
# creation.
resource "google_project_service" "compute" {
  project            = var.project_id
  service            = "compute.googleapis.com"
  disable_on_destroy = false
}
