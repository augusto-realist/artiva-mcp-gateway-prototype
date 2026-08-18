resource "google_artifact_registry_repository" "gateway" {
  project       = var.project_id
  location      = var.region
  repository_id = "artiva-mcp-gateway"
  format        = "DOCKER"
  description   = "Container images for the Artiva MCP gateway prototype (sandbox)."

  depends_on = [google_project_service.artifact_registry]
}
