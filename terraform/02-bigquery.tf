# tfdoc:file:description The sandbox dataset/table and their access rules -- data plus who can read it, colocated like 03-curated.tf's own artiva-rbac-bq module.

# The dataset/table bigquery_tools.py actually queries in this sandbox
# (Step 4 of the request chain -- see Notes/how_app_works.md). Originally
# created by hand via `bq mk` during the very first sandbox setup, before
# any Terraform existed here. Brought under management via `terraform
# import` -- write to match exactly, then import, never a blind `apply` on
# something already live.
resource "google_bigquery_dataset" "mcp_sandbox" {
  project     = var.project_id
  dataset_id  = var.wif_test_dataset_id
  location    = "US"
  description = "MCP gateway sandbox test dataset"

  # Deliberately no `access` block -- BigQuery's own default access list
  # (project owners/writers/readers + the creating user) already applies
  # and is left alone; this dataset's actual per-principal grant (the WIF
  # group) is managed separately below via google_bigquery_dataset_iam_member,
  # matching gcp-foundation-artiva's own module pattern of keeping IAM
  # grants as their own resources rather than inline `access`.
}

resource "google_bigquery_table" "test_rows" {
  project    = var.project_id
  dataset_id = google_bigquery_dataset.mcp_sandbox.dataset_id
  table_id   = "test_rows"

  schema = jsonencode([
    { name = "id", type = "INTEGER", mode = "NULLABLE" },
    { name = "label", type = "STRING", mode = "NULLABLE" },
  ])
}

# Grants the WIF group principal (not the gateway's own service account,
# see 01-identity.tf) the roles a real federated user needs.
resource "google_project_iam_member" "wif_group_job_user" {
  project = var.project_id
  role    = "roles/bigquery.jobUser"
  member  = "${module.workforce_identity.principal_set_prefix}/${var.wif_test_group}"
}

# Separate from the BigQuery-specific roles -- this is what lets a federated
# (WIF) caller attribute API usage to this project's billing/quota at all.
# Without it, BigQuery calls fail with USER_PROJECT_DENIED even though
# bigquery.dataViewer/jobUser are correctly granted. Same failure mode as
# the earlier `gcloud init` vs. ADC quota-project gotcha, but this time as a
# real IAM grant needed for a federated principal specifically.
resource "google_project_iam_member" "wif_group_service_usage" {
  project = var.project_id
  role    = "roles/serviceusage.serviceUsageConsumer"
  member  = "${module.workforce_identity.principal_set_prefix}/${var.wif_test_group}"
}

# Dataset-level roles/bigquery.dataViewer for the WIF group. A bare
# principalSet:// member string fails to parse on this resource -- the
# fix is the `iamMember:` prefix below. See
# ../../Notes/BigQuery Dataset IAM - Terraform principalSet Bug.md for the
# full root-cause writeup (an upstream provider parsing gap, not a config
# mistake), and Repos/gcp-foundation-artiva's own 03-curated.tf, which
# needed the identical fix for the real deployment.
resource "google_bigquery_dataset_iam_member" "wif_group_dataset_viewer" {
  project = var.project_id
  # Referencing the dataset resource directly, not var.wif_test_dataset_id,
  # so Terraform creates the dataset before attempting this grant on a
  # from-scratch apply.
  dataset_id = google_bigquery_dataset.mcp_sandbox.dataset_id
  role       = "roles/bigquery.dataViewer"
  member     = "iamMember:${module.workforce_identity.principal_set_prefix}/${var.wif_test_group}"
}
