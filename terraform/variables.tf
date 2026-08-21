variable "project_id" {
  description = "Sandbox GCP project ID."
  type        = string
}

variable "region" {
  description = "Region for Cloud Run and Artifact Registry. Matches gcp-foundation-artiva's own convention (region = \"us-west1\")."
  type        = string
  default     = "us-west1"
}

variable "image" {
  description = <<-EOT
    Full Artifact Registry image reference to deploy
    (REGION-docker.pkg.dev/PROJECT/REPO/gateway:TAG). Built and pushed
    separately -- Terraform only creates the Artifact Registry repo, it
    can't build the image itself. Defaults to Google's public hello-world
    container so the Cloud Run service can be created on the first apply,
    before the real image exists; update it once the real image is pushed.
  EOT
  type    = string
  default = "us-docker.pkg.dev/cloudrun/container/hello"
}

variable "auth_mode" {
  description = "AUTH_MODE for the gateway container -- \"local\" (no auth, ADC-based), \"okta\" (real Resource-Server mode -- Claude talks to Okta directly), or \"okta_broker\" (this gateway acts as the OAuth authorization server instead, routing around Claude's scope-conflict issue with this Okta org -- see oauth_broker.py)."
  type        = string
  default     = "local"
}

variable "okta_issuer" {
  description = "Okta custom authorization server issuer URI (see Notes/GCP Sandbox/Commands Run - Sandbox Setup.md)."
  type        = string
  default     = "https://integrator-5961269.okta.com/oauth2/default"
}

variable "okta_client_id" {
  description = "Okta OIDC app's Client ID (not a secret -- OAuth client IDs are public identifiers)."
  type        = string
  default     = "0oa16kp2pmySF7Cje698"
}

variable "okta_client_secret" {
  description = <<-EOT
    Okta OIDC app's client secret -- only needed for AUTH_MODE=okta_broker,
    where this gateway becomes a real Okta OAuth client itself (exchanging
    codes at Okta's /token endpoint), unlike AUTH_MODE=okta where the
    gateway never talks to Okta's /token endpoint at all. A real secret,
    unlike okta_client_id -- deliberately has no default, must be supplied
    via -var or a (gitignored) terraform.tfvars. Full Secret Manager
    integration would be the more robust choice beyond this sandbox.
  EOT
  type      = string
  default   = null
  sensitive = true
}

variable "wif_provider_id" {
  description = "Workforce Identity Provider ID inside wif_pool_id (see bigquery_iam.tf for wif_pool_id itself)."
  type        = string
  default     = "okta"
}

variable "gateway_public_url" {
  description = <<-EOT
    The Cloud Run service's own public URL, for AUTH_MODE=okta's
    resource_server_url. Cloud Run assigns this once at first creation and
    it stays stable across updates -- can't self-reference the service's own
    .uri attribute from within its own resource block (circular), so this is
    hardcoded from the already-known deployed URL rather than computed.
  EOT
  type    = string
  default = "https://artiva-mcp-gateway-ui6mrc63ra-uw.a.run.app"
}
