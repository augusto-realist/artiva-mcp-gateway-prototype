# Workforce Identity Pool + OIDC Provider (Okta -> Google STS trust config,
# Step 3 of the request chain -- see Notes/how_app_works.md). Originally
# created by hand via `gcloud iam workforce-pools create` / `providers
# create-oidc` during Phase D (see Notes/GCP Sandbox/Commands Run - Sandbox
# Setup.md and STATUS.md's Phase D section for why several of the flags
# below were needed -- e.g. the web_sso_config block was required by the
# installed gcloud CLI even though it's conceptually unused by this
# gateway's pure backend token-exchange flow).
#
# Brought under Terraform via `terraform import` (not `apply`) -- this
# provider took three separate, unrelated rounds of troubleshooting to get
# working (a missing Google-console redirect URI registered on the Okta
# side, a bogus `groups` OAuth scope request, and Okta's default
# Authorization Server missing its Access Policy). None of that Okta-side
# config is visible or managed here -- only the GCP-side trust
# configuration is. Do not `terraform destroy` this without expecting to
# redo that Okta-side setup too.
variable "wif_pool_parent" {
  description = "GCP organization resource name the workforce pool is scoped under (see `gcloud organizations list`)."
  type        = string
  default     = "organizations/328174304569"
}

resource "google_iam_workforce_pool" "artiva_sandbox" {
  workforce_pool_id = var.wif_pool_id
  parent            = var.wif_pool_parent
  location          = "global"
  display_name      = "Artiva MCP Sandbox"
  description       = "Sandbox workforce pool for testing Okta-federated BigQuery access via the MCP gateway prototype"
  session_duration  = "3600s"
}

resource "google_iam_workforce_pool_provider" "okta" {
  workforce_pool_id = google_iam_workforce_pool.artiva_sandbox.workforce_pool_id
  location          = "global"
  provider_id       = var.wif_provider_id
  display_name      = "Okta (sandbox)"
  description       = "Okta Integrator Free Plan trial, custom authorization server 'default'"

  # This is what federation.py's exchange_okta_token_for_google_token
  # actually depends on -- google.subject/google.groups is how Okta's
  # sub/groups claims become the identity BigQuery IAM later evaluates.
  attribute_mapping = {
    "google.subject" = "assertion.sub"
    "google.groups"  = "assertion.groups"
  }

  oidc {
    issuer_uri = var.okta_issuer
    client_id  = var.okta_client_id
    # Required by the provider whenever an `oidc` block is present, but not
    # actually exercised by this gateway -- it governs signing into the
    # Google Cloud Console via this identity provider, which nothing here
    # uses. The STS token-exchange federation.py performs doesn't touch
    # this config at all.
    web_sso_config {
      response_type             = "CODE"
      assertion_claims_behavior = "ONLY_ID_TOKEN_CLAIMS"
    }
  }

  # The live provider has a client_secret set (from the original manual
  # `gcloud` setup), but GCP's API only ever returns its thumbprint, never
  # the plaintext -- there's no value this config could declare that would
  # actually match. Without this, `terraform apply` would silently CLEAR
  # the live secret to match the (necessarily empty) HCL. Ignoring drift on
  # it instead: it's not exercised by this gateway's own STS token-exchange
  # flow anyway (federation.py never sends a client secret), only by the
  # unused "sign into the Cloud Console via this IdP" feature.
  lifecycle {
    ignore_changes = [oidc[0].client_secret]
  }
}
