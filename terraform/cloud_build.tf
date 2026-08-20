# Closes a real gotcha hit during Phase B (see History/CHANGELOG.md,
# 2026-08-18): newer GCP projects don't auto-grant the Compute Engine
# default service account permission to run Cloud Build, so the first
# `gcloud builds submit` on a fresh project fails until this is granted by
# hand. Bundled with the Cloud Build API itself for the same reason as
# apis.tf's bigquery.googleapis.com addition -- `gcloud builds submit` was
# already working here because someone (or the CLI's own interactive
# prompt) enabled it manually at some point; tracking it here closes that
# same reproducibility gap for a from-scratch project.
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
