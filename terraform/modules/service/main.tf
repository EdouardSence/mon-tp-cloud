# Generic, reusable Cloud Run v2 service.
# One instance per microservice (frontend / auth-service / task-service).

locals {
  use_aws_secrets = var.aws_access_key_id != "" && var.aws_secret_access_key != ""
}

resource "google_cloud_run_v2_service" "this" {
  name                = var.name
  location            = var.region
  project             = var.project_id
  deletion_protection = false

  template {
    scaling {
      min_instance_count = var.min_instances
      max_instance_count = var.max_instances
    }

    containers {
      image = var.image

      resources {
        limits   = { cpu = var.cpu, memory = var.memory }
        cpu_idle = var.cpu_idle
      }

      ports {
        container_port = var.port
      }

      dynamic "volume_mounts" {
        for_each = var.cloudsql_instance != "" ? [1] : []
        content {
          name       = "cloudsql"
          mount_path = "/cloudsql"
        }
      }

      dynamic "env" {
        for_each = var.env
        content {
          name  = env.key
          value = env.value
        }
      }

      dynamic "env" {
        for_each = local.use_aws_secrets ? [1] : []
        content {
          name = "AWS_ACCESS_KEY_ID"
          value_source {
            secret_key_ref {
              secret  = google_secret_manager_secret.aws_key_id[0].secret_id
              version = "latest"
            }
          }
        }
      }
      dynamic "env" {
        for_each = local.use_aws_secrets ? [1] : []
        content {
          name = "AWS_SECRET_ACCESS_KEY"
          value_source {
            secret_key_ref {
              secret  = google_secret_manager_secret.aws_secret[0].secret_id
              version = "latest"
            }
          }
        }
      }

      # Liveness: process is up. Readiness/startup: dependencies (DB) are reachable.
      liveness_probe {
        http_get {
          path = "/health"
        }
        initial_delay_seconds = 5
        period_seconds        = 10
      }
      startup_probe {
        http_get {
          path = var.probe_path
        }
        failure_threshold     = 5
        period_seconds        = 10
        initial_delay_seconds = 0
      }
    }

    dynamic "volumes" {
      for_each = var.cloudsql_instance != "" ? [1] : []
      content {
        name = "cloudsql"
        cloud_sql_instance {
          instances = [var.cloudsql_instance]
        }
      }
    }
  }

  traffic {
    type    = "TRAFFIC_TARGET_ALLOCATION_TYPE_LATEST"
    percent = 100
  }
}

resource "google_cloud_run_v2_service_iam_member" "public" {
  count    = var.allow_unauthenticated ? 1 : 0
  project  = var.project_id
  location = var.region
  name     = google_cloud_run_v2_service.this.name
  role     = "roles/run.invoker"
  member   = "allUsers"
}

# ─── AWS credential secrets (created only for the task-service instance) ──────

resource "google_secret_manager_secret" "aws_key_id" {
  count     = local.use_aws_secrets ? 1 : 0
  project   = var.project_id
  secret_id = "${var.name}-aws-key-id"
  replication {
    auto {}
  }
}

resource "google_secret_manager_secret_version" "aws_key_id" {
  count       = local.use_aws_secrets ? 1 : 0
  secret      = google_secret_manager_secret.aws_key_id[0].id
  secret_data = var.aws_access_key_id
}

resource "google_secret_manager_secret" "aws_secret" {
  count     = local.use_aws_secrets ? 1 : 0
  project   = var.project_id
  secret_id = "${var.name}-aws-secret"
  replication {
    auto {}
  }
}

resource "google_secret_manager_secret_version" "aws_secret" {
  count       = local.use_aws_secrets ? 1 : 0
  secret      = google_secret_manager_secret.aws_secret[0].id
  secret_data = var.aws_secret_access_key
}

data "google_project" "this" {
  count      = local.use_aws_secrets ? 1 : 0
  project_id = var.project_id
}

locals {
  run_sa = local.use_aws_secrets ? "serviceAccount:${data.google_project.this[0].number}-compute@developer.gserviceaccount.com" : ""
}

resource "google_secret_manager_secret_iam_member" "run_reads_key_id" {
  count     = local.use_aws_secrets ? 1 : 0
  project   = var.project_id
  secret_id = google_secret_manager_secret.aws_key_id[0].secret_id
  role      = "roles/secretmanager.secretAccessor"
  member    = local.run_sa
}

resource "google_secret_manager_secret_iam_member" "run_reads_secret" {
  count     = local.use_aws_secrets ? 1 : 0
  project   = var.project_id
  secret_id = google_secret_manager_secret.aws_secret[0].secret_id
  role      = "roles/secretmanager.secretAccessor"
  member    = local.run_sa
}
