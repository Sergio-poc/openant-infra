locals {
  name = var.project_name
}

# ─── Random suffix for unique naming ─────────────────────────────────────────

resource "random_id" "suffix" {
  byte_length = 4
}

# ─── GCS Bucket ───────────────────────────────────────────────────────────────

resource "google_storage_bucket" "data" {
  name                        = "${local.name}-data-${random_id.suffix.hex}"
  location                    = var.region
  force_destroy               = true
  uniform_bucket_level_access = true

  versioning {
    enabled = true
  }
}

# ─── Artifact Registry ────────────────────────────────────────────────────────

resource "google_artifact_registry_repository" "agent" {
  location      = var.region
  repository_id = "${local.name}-agent"
  format        = "DOCKER"
}

# ─── Service Account + IAM ────────────────────────────────────────────────────

resource "google_service_account" "agent" {
  account_id   = "${local.name}-agent"
  display_name = "${local.name} Agent"
}

resource "google_project_iam_member" "vertex_ai" {
  project = var.project_id
  role    = "roles/aiplatform.user"
  member  = "serviceAccount:${google_service_account.agent.email}"
}

resource "google_project_iam_member" "storage" {
  project = var.project_id
  role    = "roles/storage.objectAdmin"
  member  = "serviceAccount:${google_service_account.agent.email}"
}

# ─── Cloud Run Service ────────────────────────────────────────────────────────

resource "google_cloud_run_v2_service" "agent" {
  name     = "${local.name}-agent"
  location = var.region

  template {
    service_account = google_service_account.agent.email

    containers {
      image = "${var.region}-docker.pkg.dev/${var.project_id}/${google_artifact_registry_repository.agent.repository_id}/agent:latest"

      resources {
        limits = {
          cpu    = var.task_cpu
          memory = var.task_memory
        }
      }

      env {
        name  = "GCS_BUCKET"
        value = google_storage_bucket.data.name
      }
      env {
        name  = "MODEL_ID"
        value = var.default_model_id
      }
      env {
        name  = "USE_VERTEX_AI"
        value = "1"
      }
      env {
        name  = "GCP_REGION"
        value = var.region
      }
      env {
        name  = "GCP_PROJECT"
        value = var.project_id
      }
      env {
        name  = "STAGE"
        value = "parse"
      }
    }
  }
}
