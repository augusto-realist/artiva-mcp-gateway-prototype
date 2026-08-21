# Workforce Identity Pool + OIDC Provider -- the Okta -> Google STS trust
# config (Step 3 of the request chain -- see Notes/how_app_works.md). Not an
# upstream Cloud Foundation Fabric module (none exists for this yet, checked
# directly against GoogleCloudPlatform/cloud-foundation-fabric); hand-written
# to match Fabric's structural conventions, but the versions.tf in this
# directory deliberately does NOT carry a Fabric release comment or
# provider_meta -- that would misrepresent this as upstream-authored.
resource "google_iam_workforce_pool" "pool" {
  workforce_pool_id = var.pool_id
  parent            = var.pool_parent
  location          = "global"
  display_name      = coalesce(var.display_name, var.pool_id)
  description       = var.description
  session_duration  = var.session_duration
}

resource "google_iam_workforce_pool_provider" "okta" {
  workforce_pool_id = google_iam_workforce_pool.pool.workforce_pool_id
  location          = "global"
  provider_id       = var.provider_id
  display_name      = coalesce(var.provider_display_name, var.provider_id)
  description       = var.provider_description

  # This is what federation.py's exchange_okta_token_for_google_token
  # actually depends on -- google.subject/google.groups is how Okta's
  # sub/groups claims become the identity BigQuery IAM later evaluates.
  attribute_mapping = var.attribute_mapping

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
  # `gcloud` setup that predates this module), but GCP's API only ever
  # returns its thumbprint, never the plaintext -- there's no value this
  # config could declare that would actually match. Without this,
  # `terraform apply` would silently CLEAR the live secret to match the
  # (necessarily empty) HCL. Ignoring drift on it instead: it's not
  # exercised by this gateway's own STS token-exchange flow anyway
  # (federation.py never sends a client secret), only by the unused "sign
  # into the Cloud Console via this IdP" feature.
  lifecycle {
    ignore_changes = [oidc[0].client_secret]
  }
}
