variable "project_id" {
  description = "GCP project ID."
  type        = string
}

variable "region" {
  description = "GCP region for the Cloud Run service."
  type        = string
  default     = "europe-west1"
}

variable "environment" {
  description = "Environment name (dev / prod). Drives service name and scaling."
  type        = string
}

variable "image" {
  description = "Container image to deploy (full GAR path + tag)."
  type        = string
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
