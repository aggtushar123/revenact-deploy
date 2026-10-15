output "project_number" {
  value = data.google_project.this.number
}

output "web_url" {
  description = "Deterministic Cloud Run URL of the web service."
  value       = "https://revenact-web-${data.google_project.this.number}.${var.region}.run.app"
}

output "redis_url" {
  value = "redis://${google_memorystore_instance.valkey.endpoints[0].connections[0].psc_auto_connection[0].ip_address}:6379/0"
}

output "image_repo" {
  value = "${var.region}-docker.pkg.dev/${var.project_id}/${google_artifact_registry_repository.images.repository_id}"
}

output "workload_identity_provider" {
  value = google_iam_workload_identity_pool_provider.github.name
}

output "deployer_service_account" {
  value = google_service_account.deployer.email
}

output "media_bucket" {
  value = google_storage_bucket.media.name
}
