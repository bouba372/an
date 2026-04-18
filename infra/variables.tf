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

variable "PREFECT_DB_NAME" {
  type        = string
  description = "Prefect database name"
  default     = "prefect"
}

variable "METABASE_DB_NAME" {
  type        = string
  description = "Metabase database name"
  default     = "metabase"
}

variable "PREFECT_DB_USER" {
  type        = string
  description = "Prefect database user"
  default     = "prefect"
}

variable "METABASE_DB_USER" {
  type        = string
  description = "Metabase database user"
  default     = "metabase"
}

variable "PREFECT_DB_PASSWORD" {
  type        = string
  description = "Prefect database password"
  sensitive   = true
}

variable "METABASE_DB_PASSWORD" {
  type        = string
  description = "Metabase database password"
  sensitive   = true
}

variable "PREFECT_DB_SECRET" {
  type        = string
  description = "Secret Manager secret ID for Prefect DB password"
  default     = "prefect-db-password"
}

variable "METABASE_DB_SECRET" {
  type        = string
  description = "Secret Manager secret ID for Metabase DB password"
  default     = "metabase-db-password"
}

variable "PREFECT_SERVER_SA" {
  type        = string
  description = "Service account email used by Prefect server"
}

variable "METABASE_SA" {
  type        = string
  description = "Service account email used by Metabase"
}
