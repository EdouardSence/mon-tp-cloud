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
  description = "Fallback DB URL when Cloud SQL is disabled (ephemeral per-instance)."
  type        = string
  default     = "sqlite:////tmp/app.db"
}

variable "enable_cloud_sql" {
  description = "Provision a Cloud SQL Postgres instance and wire it to the backends."
  type        = bool
  default     = false
}

variable "db_password" {
  description = "Cloud SQL app user password (only used when enable_cloud_sql = true)."
  type        = string
  sensitive   = true
  default     = ""
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
