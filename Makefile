ifneq (,$(wildcard .env))
include .env
export
endif

DOCKER_REGISTRY ?= parleman-artifact-repo
METABASE_IMAGE ?= metabase
AIRFLOW_IMAGE ?= parleman-airflow
GCP_REGION ?= europe-west1
TERRAFORM_DIR ?= infra
METABASE_SERVICE ?= metabase
LOCAL_COMPOSE_FILE ?= infra/docker-compose.yml
SQL_INSTANCE ?= parleman-postgres
SQL_DB_VERSION ?= POSTGRES_16
SQL_EDITION ?= ENTERPRISE
SQL_TIER ?= db-custom-2-7680
AIRFLOW_DB_NAME ?= airflow
AIRFLOW_DB_USER ?= airflow
AIRFLOW_DB_SECRET ?= airflow-db-password
AIRFLOW_SA ?= ${SA_RUNNER_NAME}@${GCP_PROJECT}.iam.gserviceaccount.com

.PHONY: help
help: ## Show available make targets
	@echo "Available targets:"; \
	awk 'BEGIN {FS = ":.*## "} /^[a-zA-Z0-9_.-]+:.*## / {printf "  %-34s %s\n", $$1, $$2}' Makefile

build_metabase: ## Build image for GCP (Linux/amd64 platform)
	@echo "Building the image for GCP..."
	docker pull --platform linux/amd64 metabase/metabase:v0.56.3
	docker tag metabase/metabase:v0.56.3 europe-west1-docker.pkg.dev/${GCP_PROJECT}/${DOCKER_REGISTRY}/${METABASE_IMAGE}

push_metabase: build_metabase ## Build and push image to Artifact Registry
	docker push europe-west1-docker.pkg.dev/${GCP_PROJECT}/${DOCKER_REGISTRY}/${METABASE_IMAGE}


build_airflow_image: ## Build image for Airflow (Linux/amd64 platform)
	@echo "Building the image for GCP..."
	docker build --platform linux/amd64 -t europe-west1-docker.pkg.dev/${GCP_PROJECT}/${DOCKER_REGISTRY}/${AIRFLOW_IMAGE} -f infra/airflow/Dockerfile . 

push_airflow_image: build_airflow_image ## Build and push Airflow image to Artifact Registry
	docker push europe-west1-docker.pkg.dev/${GCP_PROJECT}/${DOCKER_REGISTRY}/${AIRFLOW_IMAGE}

airflow_up: ## Start local Airflow stack
	-@docker rm -f parleman-airflow-webserver parleman-airflow-scheduler parleman-airflow-init parleman-airflow-postgres >/dev/null 2>&1 || true
	docker compose -f ${LOCAL_COMPOSE_FILE} up -d --build airflow-postgres airflow-init airflow-webserver airflow-scheduler

airflow_down: ## Stop local Airflow stack
	docker compose -f ${LOCAL_COMPOSE_FILE} stop airflow-webserver airflow-scheduler airflow-init airflow-postgres
	-@docker rm -f parleman-airflow-webserver parleman-airflow-scheduler parleman-airflow-init parleman-airflow-postgres >/dev/null 2>&1 || true

airflow_logs: ## Follow local Airflow logs
	docker compose -f ${LOCAL_COMPOSE_FILE} logs -f airflow-init airflow-webserver airflow-scheduler airflow-postgres

terraform_init: ## Init Terraform infra workspace
	@terraform -chdir=${TERRAFORM_DIR} init

terraform_plan: terraform_init ## Preview Terraform infra changes
	@bash -lc 'set -euo pipefail; \
		: "$${AIRFLOW_DB_PASSWORD:?Set AIRFLOW_DB_PASSWORD before running this target}"; \
		TF_VAR_GCP_PROJECT="${GCP_PROJECT}" \
		TF_VAR_GCP_REGION="${GCP_REGION}" \
		TF_VAR_SQL_INSTANCE="${SQL_INSTANCE}" \
		TF_VAR_SQL_DB_VERSION="${SQL_DB_VERSION}" \
		TF_VAR_SQL_EDITION="${SQL_EDITION}" \
		TF_VAR_SQL_TIER="${SQL_TIER}" \
		TF_VAR_AIRFLOW_DB_NAME="${AIRFLOW_DB_NAME}" \
		TF_VAR_AIRFLOW_DB_USER="${AIRFLOW_DB_USER}" \
		TF_VAR_AIRFLOW_DB_PASSWORD="$${AIRFLOW_DB_PASSWORD}" \
		TF_VAR_AIRFLOW_DB_SECRET="${AIRFLOW_DB_SECRET}" \
		TF_VAR_AIRFLOW_SA="${AIRFLOW_SA}" \
		terraform -chdir=${TERRAFORM_DIR} plan'

terraform_apply: terraform_init ## Apply Terraform infra changes
	@bash -lc 'set -euo pipefail; \
		: "$${AIRFLOW_DB_PASSWORD:?Set AIRFLOW_DB_PASSWORD before running this target}"; \
		TF_VAR_GCP_PROJECT="${GCP_PROJECT}" \
		TF_VAR_GCP_REGION="${GCP_REGION}" \
		TF_VAR_SQL_INSTANCE="${SQL_INSTANCE}" \
		TF_VAR_SQL_DB_VERSION="${SQL_DB_VERSION}" \
		TF_VAR_SQL_EDITION="${SQL_EDITION}" \
		TF_VAR_SQL_TIER="${SQL_TIER}" \
		TF_VAR_AIRFLOW_DB_NAME="${AIRFLOW_DB_NAME}" \
		TF_VAR_AIRFLOW_DB_USER="${AIRFLOW_DB_USER}" \
		TF_VAR_AIRFLOW_DB_PASSWORD="$${AIRFLOW_DB_PASSWORD}" \
		TF_VAR_AIRFLOW_DB_SECRET="${AIRFLOW_DB_SECRET}" \
		TF_VAR_AIRFLOW_SA="${AIRFLOW_SA}" \
		terraform -chdir=${TERRAFORM_DIR} apply -auto-approve'

bootstrap_cloudsql_postgres: terraform_apply ## Create/ensure Cloud SQL resources for Airflow
	@echo "Cloud SQL bootstrap completed via Terraform"