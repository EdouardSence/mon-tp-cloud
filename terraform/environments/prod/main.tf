terraform {
  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 6.0"
    }
  }
  backend "gcs" {
    bucket = "mon-tp-cloud-tfstate"
    prefix = "terraform/prod"
  }
}

provider "google" {
  project = "mon-tp-cloud"
  region  = "europe-west1"
}

# Pipeline overrides these with the freshly-built per-service GAR image + SHA tag.
variable "frontend_image" {
  type    = string
  default = "europe-west1-docker.pkg.dev/mon-tp-cloud/docker/frontend:latest"
}
variable "auth_image" {
  type    = string
  default = "europe-west1-docker.pkg.dev/mon-tp-cloud/docker/auth-service:latest"
}
variable "task_image" {
  type    = string
  default = "europe-west1-docker.pkg.dev/mon-tp-cloud/docker/task-service:latest"
}

variable "aws_access_key_id" {
  type      = string
  sensitive = true
}
variable "aws_secret_access_key" {
  type      = string
  sensitive = true
}
variable "db_password" {
  type      = string
  sensitive = true
  default   = ""
}

module "env" {
  source = "../../modules/environment"

  environment           = "prod"
  frontend_image        = var.frontend_image
  auth_image            = var.auth_image
  task_image            = var.task_image
  aws_access_key_id     = var.aws_access_key_id
  aws_secret_access_key = var.aws_secret_access_key

  # Cloud SQL Postgres is fully coded and prod-ready. Disabled here to avoid
  # billing the personal free tier during the demo — flip to true and set
  # TF_VAR_db_password to provision the real instance + wire it to the backends.
  enable_cloud_sql = false
  db_password      = var.db_password
}

output "frontend_url" {
  value = module.env.frontend_url
}
output "auth_url" {
  value = module.env.auth_url
}
output "task_url" {
  value = module.env.task_url
}
