# Postgres 16 with a private IP only. pgvector ("vector" extension) is
# available on Cloud SQL; the app creates it in a migration.
resource "google_sql_database_instance" "db" {
  name                = "revenact-pg"
  database_version    = "POSTGRES_16"
  region              = var.region
  deletion_protection = true

  settings {
    tier              = var.db_tier
    edition           = "ENTERPRISE"
    availability_type = "ZONAL"
    disk_type         = "PD_SSD"
    disk_size         = 10
    disk_autoresize   = true

    ip_configuration {
      ipv4_enabled    = false
      private_network = google_compute_network.vpc.id
      ssl_mode        = "ENCRYPTED_ONLY"
    }

    # Demo data that can be re-seeded, so no point-in-time recovery; a week of
    # daily backups costs cents and covers a bad migration.
    backup_configuration {
      enabled                        = true
      point_in_time_recovery_enabled = false
      start_time                     = "20:30" # UTC, 02:00 IST

      backup_retention_settings {
        retained_backups = 7
      }
    }

    maintenance_window {
      day  = 7
      hour = 21
    }
  }

  depends_on = [google_service_networking_connection.private_services]
}

resource "google_sql_database" "app" {
  name     = "revenact"
  instance = google_sql_database_instance.db.name
}

resource "random_password" "db" {
  length  = 32
  special = false
}

resource "google_sql_user" "app" {
  name     = "revenact"
  instance = google_sql_database_instance.db.name
  password = random_password.db.result
}
