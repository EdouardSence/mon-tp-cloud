variable "enable" {
  description = "Provision the Cloud SQL instance. false = no resource created (no cost)."
  type        = bool
  default     = false
}

variable "project_id" {
  type    = string
  default = "mon-tp-cloud"
}

variable "region" {
  type    = string
  default = "europe-west1"
}

variable "environment" {
  type = string
}

variable "tier" {
  description = "Cloud SQL machine type. db-f1-micro = cheapest."
  type        = string
  default     = "db-f1-micro"
}

variable "db_name" {
  type    = string
  default = "app"
}

variable "db_user" {
  type    = string
  default = "appuser"
}

variable "db_password" {
  type      = string
  sensitive = true
  default   = ""
}
