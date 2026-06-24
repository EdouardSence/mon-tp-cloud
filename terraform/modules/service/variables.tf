variable "project_id" {
  type = string
}

variable "region" {
  type    = string
  default = "europe-west1"
}

variable "name" {
  description = "Full Cloud Run service name (caller adds the env suffix)."
  type        = string
}

variable "image" {
  type = string
}

variable "port" {
  type    = number
  default = 8080
}

variable "min_instances" {
  type    = number
  default = 0
}

variable "max_instances" {
  type    = number
  default = 3
}

variable "env" {
  description = "Plain (non-secret) environment variables."
  type        = map(string)
  default     = {}
}

variable "cpu" {
  type    = string
  default = "1"
}

variable "memory" {
  type    = string
  default = "256Mi"
}

variable "cpu_idle" {
  description = "Throttle CPU when no request is in flight. false = always-on (prod)."
  type        = bool
  default     = true
}

variable "probe_path" {
  description = "HTTP path for the startup/readiness probe."
  type        = string
  default     = "/healthz/ready"
}

variable "allow_unauthenticated" {
  type    = bool
  default = true
}

variable "cloudsql_instance" {
  description = "Cloud SQL connection name to attach via the /cloudsql socket. Empty = none."
  type        = string
  default     = ""
}

# When both are non-empty the module creates Secret Manager secrets and mounts
# them as AWS_ACCESS_KEY_ID / AWS_SECRET_ACCESS_KEY (only task-service needs them).
variable "aws_access_key_id" {
  type      = string
  sensitive = true
  default   = ""
}

variable "aws_secret_access_key" {
  type      = string
  sensitive = true
  default   = ""
}
