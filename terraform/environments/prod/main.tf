terraform {
  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 6.0"
    }
  }
}

provider "google" {
  project = "mon-tp-cloud"
  region  = "europe-west1"
}

# Pipeline sets TF_VAR_image to the freshly-built GAR image+SHA tag.
variable "image" {
  type    = string
  default = "europe-west1-docker.pkg.dev/mon-tp-cloud/docker/mon-tp-cloud:latest"
}

variable "aws_access_key_id" {
  type      = string
  sensitive = true
}

variable "aws_secret_access_key" {
  type      = string
  sensitive = true
}

module "app" {
  source = "../../modules/app"

  project_id            = "mon-tp-cloud"
  region                = "europe-west1"
  environment           = "prod"
  image                 = var.image
  aws_access_key_id     = var.aws_access_key_id
  aws_secret_access_key = var.aws_secret_access_key
}

output "url" {
  value = module.app.url
}
