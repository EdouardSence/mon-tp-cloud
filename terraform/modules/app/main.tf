# Reusable application stack (PostgreSQL + backend + frontend) for one environment.
# Each environment instantiates this module in its own Kubernetes namespace so
# dev and prod are fully isolated (separate pods, services, data, NodePort).

resource "kubernetes_namespace" "this" {
  metadata {
    name = var.environment
  }
}

locals {
  ns = kubernetes_namespace.this.metadata[0].name
}

# ─── Secrets ──────────────────────────────────────────────────────────────────

resource "kubernetes_secret" "postgres" {
  metadata {
    name      = "postgres-secret"
    namespace = local.ns
  }
  data = {
    POSTGRES_USER     = "postgres"
    POSTGRES_PASSWORD = var.postgres_password
    POSTGRES_DB       = "uploads"
  }
}

resource "kubernetes_secret" "aws" {
  metadata {
    name      = "aws-secret"
    namespace = local.ns
  }
  data = {
    AWS_ACCESS_KEY_ID     = var.aws_access_key_id
    AWS_SECRET_ACCESS_KEY = var.aws_secret_access_key
    S3_BUCKET             = var.s3_bucket
  }
}

# ─── PostgreSQL ─────────────────────────────────────────────────────────────────

resource "kubernetes_persistent_volume_claim" "postgres" {
  metadata {
    name      = "postgres-pvc"
    namespace = local.ns
  }
  spec {
    access_modes = ["ReadWriteOnce"]
    resources {
      requests = {
        storage = "1Gi"
      }
    }
  }
}

resource "kubernetes_deployment" "postgres" {
  metadata {
    name      = "postgres"
    namespace = local.ns
    labels    = { app = "postgres" }
  }
  spec {
    replicas = 1
    selector {
      match_labels = { app = "postgres" }
    }
    # Recreate, not RollingUpdate: a single-replica DB on a RWO volume must not run
    # two pods against the same data dir during an update.
    strategy {
      type = "Recreate"
    }
    template {
      metadata {
        labels = { app = "postgres" }
      }
      spec {
        container {
          name  = "postgres"
          image = "postgres:16"
          port {
            container_port = 5432
          }
          env_from {
            secret_ref {
              name = kubernetes_secret.postgres.metadata[0].name
            }
          }
          volume_mount {
            name       = "postgres-data"
            mount_path = "/var/lib/postgresql/data"
          }
          readiness_probe {
            exec {
              command = ["pg_isready", "-U", "postgres"]
            }
            initial_delay_seconds = 5
            period_seconds        = 10
          }
        }
        volume {
          name = "postgres-data"
          persistent_volume_claim {
            claim_name = kubernetes_persistent_volume_claim.postgres.metadata[0].name
          }
        }
      }
    }
  }
}

resource "kubernetes_service" "postgres" {
  metadata {
    name      = "postgres"
    namespace = local.ns
  }
  spec {
    selector = { app = "postgres" }
    type     = "ClusterIP"
    port {
      port        = 5432
      target_port = 5432
    }
  }
}

# ─── Backend ─────────────────────────────────────────────────────────────────

resource "kubernetes_deployment" "backend" {
  metadata {
    name      = "backend"
    namespace = local.ns
    labels    = { app = "backend" }
  }
  spec {
    replicas = var.backend_replicas
    selector {
      match_labels = { app = "backend" }
    }
    # Zero-downtime rolling update: never drop a pod before its replacement is Ready.
    strategy {
      type = "RollingUpdate"
      rolling_update {
        max_unavailable = 0
        max_surge       = 1
      }
    }
    template {
      metadata {
        labels = { app = "backend" }
      }
      spec {
        container {
          name              = "backend"
          image             = var.backend_image
          image_pull_policy = var.image_pull_policy
          port {
            container_port = 8080
          }
          # AWS credentials + bucket injected from the aws-secret.
          env_from {
            secret_ref {
              name = kubernetes_secret.aws.metadata[0].name
            }
          }
          # POSTGRES_* defined before DATABASE_URL — k8s $(VAR) needs prior definition.
          env {
            name = "POSTGRES_USER"
            value_from {
              secret_key_ref {
                name = kubernetes_secret.postgres.metadata[0].name
                key  = "POSTGRES_USER"
              }
            }
          }
          env {
            name = "POSTGRES_PASSWORD"
            value_from {
              secret_key_ref {
                name = kubernetes_secret.postgres.metadata[0].name
                key  = "POSTGRES_PASSWORD"
              }
            }
          }
          env {
            name = "POSTGRES_DB"
            value_from {
              secret_key_ref {
                name = kubernetes_secret.postgres.metadata[0].name
                key  = "POSTGRES_DB"
              }
            }
          }
          env {
            name  = "DATABASE_URL"
            value = "postgresql://$(POSTGRES_USER):$(POSTGRES_PASSWORD)@${kubernetes_service.postgres.metadata[0].name}:5432/$(POSTGRES_DB)"
          }
          readiness_probe {
            http_get {
              path = "/health"
              port = 8080
            }
            initial_delay_seconds = 5
            period_seconds        = 10
          }
          liveness_probe {
            http_get {
              path = "/health"
              port = 8080
            }
            initial_delay_seconds = 15
            period_seconds        = 20
          }
        }
      }
    }
  }
}

resource "kubernetes_service" "backend" {
  metadata {
    name      = "backend"
    namespace = local.ns
  }
  spec {
    selector = { app = "backend" }
    type     = "ClusterIP"
    port {
      port        = 8080
      target_port = 8080
    }
  }
}

# ─── Frontend ────────────────────────────────────────────────────────────────

resource "kubernetes_deployment" "frontend" {
  metadata {
    name      = "frontend"
    namespace = local.ns
    labels    = { app = "frontend" }
  }
  spec {
    replicas = var.frontend_replicas
    selector {
      match_labels = { app = "frontend" }
    }
    strategy {
      type = "RollingUpdate"
      rolling_update {
        max_unavailable = 0
        max_surge       = 1
      }
    }
    template {
      metadata {
        labels = { app = "frontend" }
      }
      spec {
        container {
          name              = "frontend"
          image             = var.frontend_image
          image_pull_policy = var.image_pull_policy
          port {
            container_port = 80
          }
          readiness_probe {
            http_get {
              path = "/"
              port = 80
            }
            initial_delay_seconds = 3
            period_seconds        = 10
          }
        }
      }
    }
  }
}

resource "kubernetes_service" "frontend" {
  metadata {
    name      = "frontend"
    namespace = local.ns
  }
  spec {
    selector = { app = "frontend" }
    type     = "NodePort"
    port {
      port        = 80
      target_port = 80
      node_port   = var.frontend_node_port
    }
  }
}
