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

# Pipeline overrides backend_image / frontend_image / image_pull_policy and the
# AWS secrets via TF_VAR_* env vars. Defaults below make a local `terraform apply`
# on minikube work out of the box with locally-built images.
variable "backend_image" {
  type    = string
  default = "mon-tp-cloud-backend:latest"
}

variable "frontend_image" {
  type    = string
  default = "mon-tp-cloud-frontend:latest"
}

variable "image_pull_policy" {
  type    = string
  default = "Never"
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

  environment        = "dev"
  backend_image      = var.backend_image
  frontend_image     = var.frontend_image
  image_pull_policy  = var.image_pull_policy
  backend_replicas   = 1
  frontend_replicas  = 1
  frontend_node_port = 30080

  aws_access_key_id     = var.aws_access_key_id
  aws_secret_access_key = var.aws_secret_access_key
}
