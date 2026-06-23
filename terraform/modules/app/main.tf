# Reusable Cloud Run application stack for one environment.
# Each environment gets its own Cloud Run service, isolated by name suffix.

locals {
  service_name = var.environment == "prod" ? "mon-tp-cloud" : "mon-tp-cloud-${var.environment}"
}

resource "google_cloud_run_v2_service" "app" {
  name     = local.service_name
  location = var.region
  project  = var.project_id

  deletion_protection = false

  template {
    scaling {
      min_instance_count = var.environment == "prod" ? 1 : 0
      max_instance_count = var.environment == "prod" ? 10 : 3
    }

    containers {
      image = var.image

      resources {
        limits = {
          cpu    = "1"
          memory = var.environment == "prod" ? "512Mi" : "256Mi"
        }
        # CPU always allocated in prod (zero-downtime), burst only in dev.
        cpu_idle = var.environment == "prod" ? false : true
      }

      ports {
        container_port = 8080
      }

      env {
        name  = "S3_BUCKET"
        value = var.s3_bucket
      }
      env {
        name = "AWS_ACCESS_KEY_ID"
        value_source {
          secret_key_ref {
            secret  = google_secret_manager_secret.aws_key_id.secret_id
            version = "latest"
          }
        }
      }
      env {
        name = "AWS_SECRET_ACCESS_KEY"
        value_source {
          secret_key_ref {
            secret  = google_secret_manager_secret.aws_secret.secret_id
            version = "latest"
          }
        }
      }

      # /health used by Cloud Run traffic director to gate revision promotion.
      liveness_probe {
        http_get {
          path = "/health"
        }
        initial_delay_seconds = 5
        period_seconds        = 10
      }
      # DB must respond before traffic is routed to this revision.
      startup_probe {
        http_get {
          path = "/healthz/ready"
        }
        failure_threshold     = 5
        period_seconds        = 10
        initial_delay_seconds = 0
      }
    }
  }

  traffic {
    type    = "TRAFFIC_TARGET_ALLOCATION_TYPE_LATEST"
    percent = 100
  }
}

# Make the service publicly accessible (unauthenticated).
resource "google_cloud_run_v2_service_iam_member" "public" {
  project  = var.project_id
  location = var.region
  name     = google_cloud_run_v2_service.app.name
  role     = "roles/run.invoker"
  member   = "allUsers"
}

# ─── Secrets (AWS credentials) ───────────────────────────────────────────────

resource "google_secret_manager_secret" "aws_key_id" {
  project   = var.project_id
  secret_id = "${local.service_name}-aws-key-id"
  replication {
    auto {}
  }
}

resource "google_secret_manager_secret_version" "aws_key_id" {
  secret      = google_secret_manager_secret.aws_key_id.id
  secret_data = var.aws_access_key_id
}

resource "google_secret_manager_secret" "aws_secret" {
  project   = var.project_id
  secret_id = "${local.service_name}-aws-secret"
  replication {
    auto {}
  }
}

resource "google_secret_manager_secret_version" "aws_secret" {
  secret      = google_secret_manager_secret.aws_secret.id
  secret_data = var.aws_secret_access_key
}

# Allow the Cloud Run SA to read these secrets.
data "google_project" "this" {
  project_id = var.project_id
}

locals {
  run_sa = "serviceAccount:${data.google_project.this.number}-compute@developer.gserviceaccount.com"
}

resource "google_secret_manager_secret_iam_member" "run_reads_key_id" {
  project   = var.project_id
  secret_id = google_secret_manager_secret.aws_key_id.secret_id
  role      = "roles/secretmanager.secretAccessor"
  member    = local.run_sa
}

resource "google_secret_manager_secret_iam_member" "run_reads_secret" {
  project   = var.project_id
  secret_id = google_secret_manager_secret.aws_secret.secret_id
  role      = "roles/secretmanager.secretAccessor"
  member    = local.run_sa
}
