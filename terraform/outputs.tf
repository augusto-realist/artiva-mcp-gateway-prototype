output "cloud_run_url" {
  description = "The deployed gateway's HTTPS URL. Append /mcp for the MCP endpoint itself."
  value       = google_cloud_run_v2_service.gateway.uri
}

output "artifact_registry_repo" {
  description = "Push images here, e.g. via `gcloud builds submit --tag <this>/gateway:TAG`."
  value       = "${var.region}-docker.pkg.dev/${var.project_id}/${google_artifact_registry_repository.gateway.repository_id}"
}
