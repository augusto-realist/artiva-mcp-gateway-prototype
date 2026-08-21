output "cloud_run_url" {
  description = "The deployed gateway's HTTPS URL. Append /mcp for the MCP endpoint itself."
  value       = module.gateway.service_uri
}

output "artifact_registry_repo" {
  description = "Push images here, e.g. via `gcloud builds submit --tag <this>/gateway:TAG`."
  value       = module.images.url
}
