# The dataset/table bigquery_tools.py actually queries in this sandbox
# (Step 4 of the request chain -- see Notes/how_app_works.md). Originally
# created by hand via `bq mk` during the very first sandbox setup (see
# Notes/GCP Sandbox/Commands Run - Sandbox Setup.md), before any Terraform
# existed here. Brought under management the same way as wif.tf -- write to
# match exactly, `terraform import`, never a blind `apply` on something
# already live.
resource "google_bigquery_dataset" "mcp_sandbox" {
  project     = var.project_id
  dataset_id  = var.wif_test_dataset_id
  location    = "US"
  description = "MCP gateway sandbox test dataset"

  # Deliberately no `access` block -- BigQuery's own default access list
  # (project owners/writers/readers + the creating user) already applies
  # and is left alone; this dataset's actual per-principal grant (the WIF
  # group) is managed separately via google_bigquery_dataset_iam_member in
  # bigquery_iam.tf, matching gcp-foundation-artiva's own module pattern of
  # keeping IAM grants as their own resources rather than inline `access`.
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
