# One environment = three Cloud Run services (frontend, auth, task) in their own
# namespace via name suffix. Composes the generic ../service module 3 times.

locals {
  is_prod = var.environment == "prod"
  suffix  = local.is_prod ? "" : "-${var.environment}"

  # Scaling policy: prod keeps a warm instance + scales wider; dev scales to zero.
  backend_min = local.is_prod ? 1 : 0
  backend_max = local.is_prod ? 10 : 3
  front_min   = local.is_prod ? 1 : 0
  front_max   = local.is_prod ? 5 : 2
  memory      = local.is_prod ? "512Mi" : "256Mi"
  cpu_idle    = local.is_prod ? false : true # always-on CPU in prod for zero-downtime

  # Cloud SQL when enabled, else the in-container fallback.
  database_url      = var.enable_cloud_sql ? module.database.database_url : var.database_url
  cloudsql_instance = var.enable_cloud_sql ? module.database.connection_name : ""
}

module "database" {
  source      = "../database"
  project_id  = var.project_id
  region      = var.region
  environment = var.environment
  enable      = var.enable_cloud_sql
  db_password = var.db_password
}

module "auth" {
  source     = "../service"
  project_id = var.project_id
  region     = var.region

  name              = "mon-tp-cloud-auth${local.suffix}"
  image             = var.auth_image
  min_instances     = local.backend_min
  max_instances     = local.backend_max
  memory            = local.memory
  cpu_idle          = local.cpu_idle
  probe_path        = "/healthz/ready"
  cloudsql_instance = local.cloudsql_instance
  env = {
    DATABASE_URL = local.database_url
  }
}

module "task" {
  source     = "../service"
  project_id = var.project_id
  region     = var.region

  name              = "mon-tp-cloud-task${local.suffix}"
  image             = var.task_image
  min_instances     = local.backend_min
  max_instances     = local.backend_max
  memory            = local.memory
  cpu_idle          = local.cpu_idle
  probe_path        = "/healthz/ready"
  cloudsql_instance = local.cloudsql_instance
  env = {
    DATABASE_URL     = local.database_url
    S3_BUCKET        = var.s3_bucket
    AUTH_SERVICE_URL = module.auth.url # synchronous token verification
  }
  aws_access_key_id     = var.aws_access_key_id
  aws_secret_access_key = var.aws_secret_access_key
}

module "frontend" {
  source     = "../service"
  project_id = var.project_id
  region     = var.region

  name          = "mon-tp-cloud-frontend${local.suffix}"
  image         = var.frontend_image
  port          = 80
  min_instances = local.front_min
  max_instances = local.front_max
  memory        = "128Mi"
  cpu_idle      = local.cpu_idle
  probe_path    = "/health" # nginx static endpoint; no DB dependency
  env = {
    TASK_API_URL = module.task.url
    AUTH_API_URL = module.auth.url
  }
}
