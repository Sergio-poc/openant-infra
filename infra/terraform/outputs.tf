output "bucket_name" {
  value = google_storage_bucket.data.name
}

output "artifact_registry_url" {
  value = "${var.region}-docker.pkg.dev/${var.project_id}/${google_artifact_registry_repository.agent.repository_id}"
}

output "cloud_run_service_url" {
  value = google_cloud_run_v2_service.agent.uri
}

output "service_account_email" {
  value = google_service_account.agent.email
}
