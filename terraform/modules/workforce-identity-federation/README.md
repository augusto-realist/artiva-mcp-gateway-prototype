# workforce-identity-federation

Creates a GCP Workforce Identity Pool and an OIDC Provider trusting Okta, for federating Okta-authenticated users into Google-recognized identities. Not an upstream Cloud Foundation Fabric module (none exists yet) -- hand-written to match Fabric's file-layout conventions, but not claiming Fabric authorship (see `versions.tf`).

This is the GCP-side half of the trust relationship only. The Okta-side configuration (the OIDC app, its groups, an Access Policy on the Authorization Server) lives entirely in Okta and isn't managed here -- see `Notes/GCP Sandbox/Commands Run - Sandbox Setup.md`.

## Example usage

```hcl
module "workforce_identity" {
  source          = "./modules/workforce-identity-federation"
  pool_id         = "artiva-sandbox"
  pool_parent     = "organizations/328174304569"
  provider_id     = "okta"
  okta_issuer     = "https://integrator-5961269.okta.com/oauth2/default"
  okta_client_id  = "0oa16kp2pmySF7Cje698"
}
```

Then, to grant an Okta group access to something (e.g. a BigQuery dataset):

```hcl
member = "iamMember:${module.workforce_identity.principal_set_prefix}/artiva-clinical-test"
```

## Variables

| name | description | type | required | default |
| :---- | :---- | :---- | :---: | :---- |
| pool_id | Workforce Identity Pool ID. | `string` | ✓ | |
| pool_parent | GCP organization resource name the pool is scoped under. | `string` | ✓ | |
| provider_id | Workforce Identity Provider ID inside the pool. | `string` | ✓ | |
| okta_issuer | Okta custom authorization server issuer URI. | `string` | ✓ | |
| okta_client_id | Okta OIDC app's Client ID (not a secret). | `string` | ✓ | |
| display_name | Display name for the pool. | `string` | | `null` |
| description | Description for the pool. | `string` | | `null` |
| session_duration | How long federated sessions last. | `string` | | `"3600s"` |
| provider_display_name | Display name for the OIDC provider. | `string` | | `null` |
| provider_description | Description for the OIDC provider. | `string` | | `null` |
| attribute_mapping | Maps assertion claims onto Google attributes. | `map(string)` | | `google.subject`/`google.groups` mapping |

(Hand-maintained, not machine-generated -- see the sandbox's own Terraform Reference doc for why. Keep in sync with `variables.tf` by hand.)

## Outputs

| name | description |
| :---- | :---- |
| pool_id | The pool's ID. |
| provider_id | The provider's ID. |
| principal_set_prefix | Prefix for building `principalSet://` member strings -- append `/group/<okta_group_name>`. |
