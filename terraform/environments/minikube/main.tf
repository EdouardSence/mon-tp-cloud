terraform {
  required_providers {
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 2.0"
    }
  }
}

# Lit le kubeconfig local (minikube context).
provider "kubernetes" {
  config_path    = "~/.kube/config"
  config_context = "minikube"
}

variable "image" {
  type    = string
  default = "mon-tp-cloud:latest"
}

variable "aws_access_key_id" {
  type      = string
  sensitive = true
}

variable "aws_secret_access_key" {
  type      = string
  sensitive = true
}

variable "s3_bucket" {
  type    = string
  default = ""
}

# ─── Secret app ──────────────────────────────────────────────────────────────

resource "kubernetes_secret" "app" {
  metadata {
    name = "app-secret"
  }
  data = {
    DATABASE_URL          = "postgresql://postgres:postgres@postgres:5432/uploads"
    AWS_ACCESS_KEY_ID     = var.aws_access_key_id
    AWS_SECRET_ACCESS_KEY = var.aws_secret_access_key
    S3_BUCKET             = var.s3_bucket
  }
}

# ─── Deployment ──────────────────────────────────────────────────────────────

resource "kubernetes_deployment" "app" {
  metadata {
    name = "mon-tp-cloud"
    labels = {
      app = "mon-tp-cloud"
    }
  }

  spec {
    replicas = 2

    selector {
      match_labels = {
        app = "mon-tp-cloud"
      }
    }

    template {
      metadata {
        labels = {
          app = "mon-tp-cloud"
        }
      }

      spec {
        container {
          name              = "app"
          image             = var.image
          image_pull_policy = "Never"

          port {
            container_port = 8080
          }

          env_from {
            secret_ref {
              name = kubernetes_secret.app.metadata[0].name
            }
          }

          # Désactive liveness+readiness le temps que l'app démarre (et que la DB répond).
          startup_probe {
            http_get {
              path = "/healthz/ready"
              port = 8080
            }
            failure_threshold = 10
            period_seconds    = 5
          }

          # Retire le pod du Service si la DB est injoignable → zéro downtime.
          readiness_probe {
            http_get {
              path = "/healthz/ready"
              port = 8080
            }
            initial_delay_seconds = 0
            period_seconds        = 10
            failure_threshold     = 3
          }

          # Redémarre le container si le process Flask est mort.
          liveness_probe {
            http_get {
              path = "/health"
              port = 8080
            }
            initial_delay_seconds = 0
            period_seconds        = 10
            failure_threshold     = 3
          }
        }
      }
    }
  }
}

# ─── Service (NodePort 30080) ─────────────────────────────────────────────────

resource "kubernetes_service" "app" {
  metadata {
    name = "mon-tp-cloud"
  }

  spec {
    selector = {
      app = "mon-tp-cloud"
    }

    type = "NodePort"

    port {
      port        = 80
      target_port = 8080
      node_port   = 30083
    }
  }
}

output "url" {
  value = "http://$(minikube ip):30083"
}
