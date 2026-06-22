terraform {
  required_providers {
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 2.0"
    }
  }
}

provider "kubernetes" {
  config_path    = "~/.kube/config"
  config_context = "minikube"
}

# Prod pulls immutable, tagged images from the registry. The CD pipeline overrides
# backend_image / frontend_image with the freshly-built commit SHA tag, and supplies
# the AWS secrets via TF_VAR_*. Replace OWNER with your GitHub org/user.
variable "backend_image" {
  type    = string
  default = "ghcr.io/edouardsence/mon-tp-cloud-backend:stable"
}

variable "frontend_image" {
  type    = string
  default = "ghcr.io/edouardsence/mon-tp-cloud-frontend:stable"
}

variable "aws_access_key_id" {
  type      = string
  default   = ""
  sensitive = true
}

variable "aws_secret_access_key" {
  type      = string
  default   = ""
  sensitive = true
}

module "app" {
  source = "../../modules/app"

  environment        = "prod"
  backend_image      = var.backend_image
  frontend_image     = var.frontend_image
  image_pull_policy  = "IfNotPresent"
  backend_replicas   = 2 # multiple replicas so the rolling update keeps serving traffic
  frontend_replicas  = 2
  frontend_node_port = 30090

  aws_access_key_id     = var.aws_access_key_id
  aws_secret_access_key = var.aws_secret_access_key
}
