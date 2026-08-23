output "pool_id" {
  description = "The Workforce Identity Pool's ID."
  value       = google_iam_workforce_pool.pool.workforce_pool_id
}

output "provider_id" {
  description = "The Workforce Identity Provider's ID."
  value       = google_iam_workforce_pool_provider.okta.provider_id
}

output "principal_set_prefix" {
  description = "Prefix for building principalSet:// member strings for groups federated through this provider -- append /group/<okta_group_name>."
  value       = "principalSet://iam.googleapis.com/locations/global/workforcePools/${google_iam_workforce_pool.pool.workforce_pool_id}/group"
}
