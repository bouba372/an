terraform {
  required_version = ">= 1.5.0"

  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 6.0"
    }
  }
}

provider "google" {
  project = var.GCP_PROJECT
  region  = var.GCP_REGION
}

resource "google_project_service" "services" {
  for_each = toset([
    "run.googleapis.com",
    "secretmanager.googleapis.com",
    "sqladmin.googleapis.com",
  ])

  project            = var.GCP_PROJECT
  service            = each.value
  disable_on_destroy = false
}

resource "google_sql_database_instance" "postgres" {
  name                = var.SQL_INSTANCE
  region              = var.GCP_REGION
  database_version    = var.SQL_DB_VERSION
  deletion_protection = true

  settings {
    edition = var.SQL_EDITION
    tier    = var.SQL_TIER

    disk_autoresize = true
    disk_size       = 20
    disk_type       = "PD_SSD"

    backup_configuration {
      enabled                        = true
      point_in_time_recovery_enabled = true
    }

    ip_configuration {
      ipv4_enabled = true
    }
  }

  depends_on = [google_project_service.services]
}

resource "google_sql_database" "prefect" {
  name     = var.PREFECT_DB_NAME
  instance = google_sql_database_instance.postgres.name
}

resource "google_sql_database" "metabase" {
  name     = var.METABASE_DB_NAME
  instance = google_sql_database_instance.postgres.name
}

resource "google_sql_user" "prefect" {
  instance = google_sql_database_instance.postgres.name
  name     = var.PREFECT_DB_USER
  password = var.PREFECT_DB_PASSWORD
}

resource "google_sql_user" "metabase" {
  instance = google_sql_database_instance.postgres.name
  name     = var.METABASE_DB_USER
  password = var.METABASE_DB_PASSWORD
}

resource "google_secret_manager_secret" "prefect_db_password" {
  project   = var.GCP_PROJECT
  secret_id = var.PREFECT_DB_SECRET

  replication {
    auto {}
  }

  depends_on = [google_project_service.services]
}

resource "google_secret_manager_secret_version" "prefect_db_password" {
  secret      = google_secret_manager_secret.prefect_db_password.id
  secret_data = var.PREFECT_DB_PASSWORD
}

resource "google_secret_manager_secret" "metabase_db_password" {
  project   = var.GCP_PROJECT
  secret_id = var.METABASE_DB_SECRET

  replication {
    auto {}
  }

  depends_on = [google_project_service.services]
}

resource "google_secret_manager_secret_version" "metabase_db_password" {
  secret      = google_secret_manager_secret.metabase_db_password.id
  secret_data = var.METABASE_DB_PASSWORD
}

resource "google_project_iam_member" "prefect_cloudsql_client" {
  project = var.GCP_PROJECT
  role    = "roles/cloudsql.client"
  member  = "serviceAccount:${var.PREFECT_SERVER_SA}"
}

resource "google_project_iam_member" "prefect_secret_accessor" {
  project = var.GCP_PROJECT
  role    = "roles/secretmanager.secretAccessor"
  member  = "serviceAccount:${var.PREFECT_SERVER_SA}"
}

resource "google_project_iam_member" "metabase_cloudsql_client" {
  project = var.GCP_PROJECT
  role    = "roles/cloudsql.client"
  member  = "serviceAccount:${var.METABASE_SA}"
}

resource "google_project_iam_member" "metabase_secret_accessor" {
  project = var.GCP_PROJECT
  role    = "roles/secretmanager.secretAccessor"
  member  = "serviceAccount:${var.METABASE_SA}"
}

output "sql_connection_name" {
  value = google_sql_database_instance.postgres.connection_name
}

output "prefect_db_secret" {
  value = google_secret_manager_secret.prefect_db_password.secret_id
}

output "metabase_db_secret" {
  value = google_secret_manager_secret.metabase_db_password.secret_id
}
