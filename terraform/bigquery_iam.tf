variable "wif_pool_id" {
  description = "Workforce Identity Pool ID (created outside Terraform, via gcloud -- see ../../Notes/GCP Sandbox/Commands Run - Sandbox Setup.md)."
  type        = string
  default     = "artiva-sandbox"
}

variable "wif_test_group" {
  description = "Okta group name to grant sandbox BigQuery access to, via the WIF pool's principalSet."
  type        = string
  default     = "artiva-clinical-test"
}

variable "wif_test_dataset_id" {
  description = "Dataset to test the dataset-level IAM grant against (created manually via bq, not Terraform-managed)."
  type        = string
  default     = "mcp_sandbox"
}

locals {
  wif_group_principal = "principalSet://iam.googleapis.com/locations/global/workforcePools/${var.wif_pool_id}/group/${var.wif_test_group}"
}

# Original finding: dataset-level roles/bigquery.dataViewer for
# local.wif_group_principal, granted the naive way --
# google_bigquery_dataset_iam_member with `member = local.wif_group_principal`
# (a bare principalSet:// string) -- fails to parse. This project's
# `bq add-iam-policy-binding` also hit a separate "requires allowlisting"
# error on the newer unified IAM-policy API path. What worked at the time:
# patching the dataset's legacy access-control list directly (`bq show
# --format=prettyjson` -> add an access entry
# `{"role": "READER", "iamMember": "<principal>"}` as a FLAT STRING, not a
# nested object -> `bq update --source=<file>`). Applied manually, once.
#
# RE-EXAMINED: the closed upstream issue (#16607, fixed via PR #17292) turns
# out to cover both principal:// and principalSet://, not just individual
# identities as first assumed -- but the fix requires an `iamMember:` prefix
# on the member string (confirmed in the current provider docs for this
# resource: "iamMember:{principal} -- used for workload/workforce federated
# identities (principal, principalSet)"), which the naive attempt above never
# included. #26255 (still open) turned out to be an unrelated GKE Workload
# Identity bug (missing "@" in `serviceAccount:...svc.id.goog[...]` members),
# not this WIF/principalSet case at all.
#
# Testing that hypothesis below with `wif_group_dataset_viewer_iam_member_test`
# -- if it applies cleanly, the real fix is a one-line prefix change, not the
# legacy-ACL workaround, and this needs carrying into gcp-foundation-artiva's
# modules/bigquery-dataset / 03-curated.tf's artiva-rbac-bq module for real.
resource "google_bigquery_dataset_iam_member" "wif_group_dataset_viewer_iam_member_test" {
  project    = var.project_id
  dataset_id = var.wif_test_dataset_id
  role       = "roles/bigquery.dataViewer"
  member     = "iamMember:${local.wif_group_principal}"
}

resource "google_project_iam_member" "wif_group_job_user" {
  project = var.project_id
  role    = "roles/bigquery.jobUser"
  member  = local.wif_group_principal
}

# Separate from the BigQuery-specific roles above -- this is what lets a
# federated (WIF) caller attribute API usage to this project's billing/quota
# at all. Without it, BigQuery calls fail with USER_PROJECT_DENIED even
# though bigquery.dataViewer/jobUser are correctly granted. Same failure
# mode as the earlier `gcloud init` vs. ADC quota-project gotcha, but this
# time as a real IAM grant needed for a federated principal specifically.
resource "google_project_iam_member" "wif_group_service_usage" {
  project = var.project_id
  role    = "roles/serviceusage.serviceUsageConsumer"
  member  = local.wif_group_principal
}
