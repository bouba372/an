variable "GCP_PROJECT" {
  type        = string
  description = "Google Cloud project ID"
}

variable "GCP_REGION" {
  type        = string
  description = "Google Cloud region"
  default     = "europe-west1"
}

variable "SQL_INSTANCE" {
  type        = string
  description = "Cloud SQL instance name"
  default     = "parleman-postgres"
}

variable "SQL_DB_VERSION" {
  type        = string
  description = "Cloud SQL database version"
  default     = "POSTGRES_16"
}

variable "SQL_EDITION" {
  type        = string
  description = "Cloud SQL edition"
  default     = "ENTERPRISE"
}

variable "SQL_TIER" {
  type        = string
  description = "Cloud SQL machine tier"
  default     = "db-custom-2-7680"
}

variable "AIRFLOW_DB_NAME" {
  type        = string
  description = "Airflow metadata database name"
  default     = "airflow"
}

variable "AIRFLOW_DB_USER" {
  type        = string
  description = "Airflow metadata database user"
  default     = "airflow"
}

variable "AIRFLOW_DB_PASSWORD" {
  type        = string
  description = "Airflow metadata database password"
  sensitive   = true
}

variable "AIRFLOW_DB_SECRET" {
  type        = string
  description = "Secret Manager secret ID for Airflow DB password"
  default     = "airflow-db-password"
}

variable "AIRFLOW_SA" {
  type        = string
  description = "Service account email used by Airflow"
}
