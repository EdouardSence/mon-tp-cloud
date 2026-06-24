variable "project_id" {
  type    = string
  default = "mon-tp-cloud"
}

variable "region" {
  type    = string
  default = "europe-west1"
}

variable "environment" {
  description = "dev / prod — drives service names and scaling."
  type        = string
}

variable "frontend_image" {
  type = string
}

variable "auth_image" {
  type = string
}

variable "task_image" {
  type = string
}

variable "database_url" {
  description = "Postgres URL shared by both backends. Point at Cloud SQL for real prod."
  type        = string
  default     = "sqlite:////tmp/app.db" # ponytail: ephemeral per-instance; swap for Cloud SQL
}

variable "s3_bucket" {
  type    = string
  default = "ynov-s3-bucket-esence-904639295906-eu-west-1-an"
}

variable "aws_access_key_id" {
  type      = string
  sensitive = true
}

variable "aws_secret_access_key" {
  type      = string
  sensitive = true
}
