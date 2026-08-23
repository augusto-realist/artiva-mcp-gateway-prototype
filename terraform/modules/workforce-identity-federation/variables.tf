variable "pool_id" {
  description = "Workforce Identity Pool ID."
  type        = string
}

variable "pool_parent" {
  description = "GCP organization resource name the pool is scoped under (see `gcloud organizations list`) -- pools are org-level, not project-level."
  type        = string
}

variable "provider_id" {
  description = "Workforce Identity Provider ID inside the pool."
  type        = string
}

variable "display_name" {
  description = "Display name for the pool."
  type        = string
  default     = null
}

variable "description" {
  description = "Description for the pool."
  type        = string
  default     = null
}

variable "session_duration" {
  description = "How long federated sessions from this pool last."
  type        = string
  default     = "3600s"
}

variable "provider_display_name" {
  description = "Display name for the OIDC provider."
  type        = string
  default     = null
}

variable "provider_description" {
  description = "Description for the OIDC provider."
  type        = string
  default     = null
}

variable "okta_issuer" {
  description = "Okta custom authorization server issuer URI."
  type        = string
}

variable "okta_client_id" {
  description = "Okta OIDC app's Client ID (not a secret -- OAuth client IDs are public identifiers)."
  type        = string
}

variable "okta_client_secret" {
  description = <<-EOT
    Okta OIDC app's client secret -- a genuine, confirmed exception to this
    project's "never pass secrets through Terraform" principle. Google's API
    requires it when CREATING a new Workforce Identity Pool Provider (not
    when importing one that already exists on Google's side) -- confirmed
    directly, not assumed: omitting it fails with "Missing OIDC Client
    Secret". Leave null (the default) when managing an already-imported
    provider, where lifecycle.ignore_changes means it's never needed; only
    supply it (via -var, never a committed .tfvars) when genuinely creating
    a provider from scratch. Ends up in this module's state -- unlike every
    other secret in this project, there is no way to avoid that here, since
    Terraform must supply it as a literal resource argument to create the
    resource at all.
  EOT
  type      = string
  default   = null
  sensitive = true
}

variable "attribute_mapping" {
  description = "Maps assertion claims from the OIDC provider onto Google attributes."
  type        = map(string)
  default = {
    "google.subject" = "assertion.sub"
    "google.groups"  = "assertion.groups"
  }
}
