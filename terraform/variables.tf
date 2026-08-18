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
