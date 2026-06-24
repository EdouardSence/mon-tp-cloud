# Connection name used by the Cloud Run Cloud SQL connector (/cloudsql mount).
output "connection_name" {
  value = var.enable ? google_sql_database_instance.postgres[0].connection_name : ""
}

# SQLAlchemy URL over the Cloud SQL unix socket. Empty when disabled.
output "database_url" {
  value     = var.enable ? "postgresql://${var.db_user}:${var.db_password}@/${var.db_name}?host=/cloudsql/${google_sql_database_instance.postgres[0].connection_name}" : ""
  sensitive = true
}
