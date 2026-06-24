# Cloud SQL Postgres — gated by var.enable. When false, nothing is created and
# the environment falls back to the in-container DB (no cost).

resource "google_sql_database_instance" "postgres" {
  count               = var.enable ? 1 : 0
  name                = "mon-tp-cloud-${var.environment}-pg"
  project             = var.project_id
  region              = var.region
  database_version    = "POSTGRES_15"
  deletion_protection = false

  settings {
    tier              = var.tier
    availability_type = "ZONAL" # SECONDARY/REGIONAL for HA prod — costs more
    disk_size         = 10
  }
}

resource "google_sql_database" "app" {
  count    = var.enable ? 1 : 0
  name     = var.db_name
  project  = var.project_id
  instance = google_sql_database_instance.postgres[0].name
}

resource "google_sql_user" "app" {
  count    = var.enable ? 1 : 0
  name     = var.db_user
  project  = var.project_id
  instance = google_sql_database_instance.postgres[0].name
  password = var.db_password
}
