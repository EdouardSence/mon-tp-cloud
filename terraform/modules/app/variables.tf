variable "environment" {
  description = "Environment name — used as the Kubernetes namespace (dev / prod)."
  type        = string
}

variable "backend_image" {
  description = "Backend container image (registry/name:tag)."
  type        = string
}

variable "frontend_image" {
  description = "Frontend container image (registry/name:tag)."
  type        = string
}

variable "image_pull_policy" {
  description = "Never for locally-built minikube images, IfNotPresent/Always for a registry."
  type        = string
  default     = "IfNotPresent"
}

variable "backend_replicas" {
  type    = number
  default = 1
}

variable "frontend_replicas" {
  type    = number
  default = 1
}

variable "frontend_node_port" {
  description = "NodePort the frontend is exposed on (must be unique per env on the same node)."
  type        = number
  default     = 30080
}

variable "postgres_password" {
  type      = string
  default   = "postgres"
  sensitive = true
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

variable "s3_bucket" {
  type    = string
  default = "ynov-s3-bucket-esence-904639295906-eu-west-1-an"
}
