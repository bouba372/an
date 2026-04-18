ifneq (,$(wildcard .env))
include .env
export
endif

DOCKER_REGISTRY ?= parleman-artifact-repo
METABASE_IMAGE ?= metabase
GCP_REGION ?= europe-west1
TERRAFORM_DIR ?= infra
PREFECT_SERVER_SERVICE ?= prefect-server
PREFECT_WORKER_SERVICE ?= prefect-worker
METABASE_SERVICE ?= metabase
SQL_INSTANCE ?= parleman-postgres
SQL_DB_VERSION ?= POSTGRES_16
SQL_EDITION ?= ENTERPRISE
SQL_TIER ?= db-custom-2-7680
PREFECT_DB_NAME ?= prefect
METABASE_DB_NAME ?= metabase
PREFECT_DB_USER ?= prefect
METABASE_DB_USER ?= metabase
PREFECT_DB_SECRET ?= prefect-db-password
METABASE_DB_SECRET ?= metabase-db-password
PREFECT_SERVER_SA ?= ${SA_WORKER_NAME}@${GCP_PROJECT}.iam.gserviceaccount.com
METABASE_SA ?= ${SA_RUNNER_NAME}@${GCP_PROJECT}.iam.gserviceaccount.com

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


build_prefect_worker: ## Build image for GCP (Linux/amd64 platform)
	@echo "Building the image for GCP..."
	docker build --platform linux/amd64 -t europe-west1-docker.pkg.dev/${GCP_PROJECT}/${DOCKER_REGISTRY}/prefect-worker -f infra/prefect/Dockerfile . 

push_prefect_worker: build_prefect_worker ## Build and push image to Artifact Registry
	docker push europe-west1-docker.pkg.dev/${GCP_PROJECT}/${DOCKER_REGISTRY}/prefect-worker

deploy_prefect_worker:
	gcloud run deploy prefect-worker \
		--project ${GCP_PROJECT} \
		--image=europe-west1-docker.pkg.dev/${GCP_PROJECT}/${DOCKER_REGISTRY}/prefect-worker \
		--set-env-vars PREFECT_API_URL=${PREFECT_API_URL} \
		--service-account ${SA_WORKER_NAME}@${GCP_PROJECT}.iam.gserviceaccount.com \
		--no-cpu-throttling \
		--min-instances 1 --memory=2Gi \
		--startup-probe httpGet.port=8080,httpGet.path=/health,initialDelaySeconds=100,periodSeconds=20,timeoutSeconds=20 \
		--args "prefect","worker","start","--install-policy","never","--with-healthcheck","-p","parleman-work-pool","-t","cloud-run"

deploy_flows_on_work_pool: push_prefect_worker deploy_prefect_worker
	prefect deploy

setup_prefect_variables:
	prefect variable set gcp-project ${GCP_PROJECT}
	prefect variable set bq-dataset ${BQ_DATASET}
	prefect variable set service-account-info ${SERVICE_ACCOUNT_INFO}

	# Docker et images
	prefect variable set docker-registry ${DOCKER_REGISTRY}
	prefect variable set metabase-image ${METABASE_IMAGE}

	# API et infrastructure
	prefect variable set prefect-api-url ${PREFECT_API_URL}

	# URLs externes des données
	prefect variable set debat-url ${DEBAT_URL}
	prefect variable set deputes-url ${DEPUTES_URL}
	prefect variable set scrutins-url ${SCRUTINS_URL}
	prefect variable set dossiers-legislatifs-url ${DOSSIERS_LEGISLATIFS_URL}
	prefect variable set questions-ecrites-url ${QUESTIONS_ECRITES_URL}

deploy_flows: ## Deploy all flows from prefect.yaml
	direnv exec . uv run prefect deploy --all --no-prompt --prefect-file prefect.yaml

prefect_local_up: ## Start local Prefect server + worker in one command
	@bash -lc 'set -euo pipefail; \
		direnv exec . uv sync --frozen; \
		direnv exec . uv run prefect server start --host 127.0.0.1 > /tmp/parleman-prefect-server.log 2>&1 & \
		server_pid=$$!; \
		trap "kill $$server_pid" EXIT INT TERM; \
		for i in $$(seq 1 30); do \
			if curl -sf http://127.0.0.1:4200/api/health > /dev/null; then \
				break; \
			fi; \
			sleep 1; \
		done; \
		curl -sf http://127.0.0.1:4200/api/health > /dev/null || { echo "Prefect local API unavailable on http://127.0.0.1:4200"; exit 1; }; \
		direnv exec . uv run prefect work-pool create parleman-work-pool --type process --overwrite > /dev/null; \
		echo "Prefect local server started (PID $$server_pid). Logs: /tmp/parleman-prefect-server.log"; \
		echo "Starting worker on pool parleman-work-pool..."; \
		direnv exec . uv run prefect worker start --pool parleman-work-pool'

terraform_init: ## Init Terraform infra workspace
	@terraform -chdir=${TERRAFORM_DIR} init

terraform_plan: terraform_init ## Preview Terraform infra changes
	@bash -lc 'set -euo pipefail; \
		: "$${PREFECT_DB_PASSWORD:?Set PREFECT_DB_PASSWORD before running this target}"; \
		: "$${METABASE_DB_PASSWORD:?Set METABASE_DB_PASSWORD before running this target}"; \
		TF_VAR_GCP_PROJECT="${GCP_PROJECT}" \
		TF_VAR_GCP_REGION="${GCP_REGION}" \
		TF_VAR_SQL_INSTANCE="${SQL_INSTANCE}" \
		TF_VAR_SQL_DB_VERSION="${SQL_DB_VERSION}" \
		TF_VAR_SQL_EDITION="${SQL_EDITION}" \
		TF_VAR_SQL_TIER="${SQL_TIER}" \
		TF_VAR_PREFECT_DB_NAME="${PREFECT_DB_NAME}" \
		TF_VAR_METABASE_DB_NAME="${METABASE_DB_NAME}" \
		TF_VAR_PREFECT_DB_USER="${PREFECT_DB_USER}" \
		TF_VAR_METABASE_DB_USER="${METABASE_DB_USER}" \
		TF_VAR_PREFECT_DB_PASSWORD="$${PREFECT_DB_PASSWORD}" \
		TF_VAR_METABASE_DB_PASSWORD="$${METABASE_DB_PASSWORD}" \
		TF_VAR_PREFECT_DB_SECRET="${PREFECT_DB_SECRET}" \
		TF_VAR_METABASE_DB_SECRET="${METABASE_DB_SECRET}" \
		TF_VAR_PREFECT_SERVER_SA="${PREFECT_SERVER_SA}" \
		TF_VAR_METABASE_SA="${METABASE_SA}" \
		terraform -chdir=${TERRAFORM_DIR} plan'

terraform_apply: terraform_init ## Apply Terraform infra changes
	@bash -lc 'set -euo pipefail; \
		: "$${PREFECT_DB_PASSWORD:?Set PREFECT_DB_PASSWORD before running this target}"; \
		: "$${METABASE_DB_PASSWORD:?Set METABASE_DB_PASSWORD before running this target}"; \
		TF_VAR_GCP_PROJECT="${GCP_PROJECT}" \
		TF_VAR_GCP_REGION="${GCP_REGION}" \
		TF_VAR_SQL_INSTANCE="${SQL_INSTANCE}" \
		TF_VAR_SQL_DB_VERSION="${SQL_DB_VERSION}" \
		TF_VAR_SQL_EDITION="${SQL_EDITION}" \
		TF_VAR_SQL_TIER="${SQL_TIER}" \
		TF_VAR_PREFECT_DB_NAME="${PREFECT_DB_NAME}" \
		TF_VAR_METABASE_DB_NAME="${METABASE_DB_NAME}" \
		TF_VAR_PREFECT_DB_USER="${PREFECT_DB_USER}" \
		TF_VAR_METABASE_DB_USER="${METABASE_DB_USER}" \
		TF_VAR_PREFECT_DB_PASSWORD="$${PREFECT_DB_PASSWORD}" \
		TF_VAR_METABASE_DB_PASSWORD="$${METABASE_DB_PASSWORD}" \
		TF_VAR_PREFECT_DB_SECRET="${PREFECT_DB_SECRET}" \
		TF_VAR_METABASE_DB_SECRET="${METABASE_DB_SECRET}" \
		TF_VAR_PREFECT_SERVER_SA="${PREFECT_SERVER_SA}" \
		TF_VAR_METABASE_SA="${METABASE_SA}" \
		terraform -chdir=${TERRAFORM_DIR} apply -auto-approve'

bootstrap_cloudsql_postgres: terraform_apply ## Create/ensure Cloud SQL resources for Prefect+Metabase
	@echo "Cloud SQL bootstrap completed via Terraform"

deploy_prefect_server: bootstrap_cloudsql_postgres ## Deploy Prefect server to Cloud Run (public) backed by Cloud SQL
	@bash -lc 'set -euo pipefail; \
		conn="$$(gcloud sql instances describe ${SQL_INSTANCE} --project ${GCP_PROJECT} --format="value(connectionName)")"; \
		prefect_db_password="$$(gcloud secrets versions access latest --secret=${PREFECT_DB_SECRET} --project ${GCP_PROJECT})"; \
		prefect_db_password_escaped="$$(PREFECT_DB_PASSWORD="$$prefect_db_password" python3 -c "import os, urllib.parse; print(urllib.parse.quote(os.environ[\"PREFECT_DB_PASSWORD\"], safe=\"\"))")"; \
		prefect_db_url="postgresql+asyncpg://${PREFECT_DB_USER}:$${prefect_db_password_escaped}@/${PREFECT_DB_NAME}?host=/cloudsql/$${conn}"; \
		gcloud run deploy ${PREFECT_SERVER_SERVICE} \
			--project ${GCP_PROJECT} \
			--region ${GCP_REGION} \
			--service-account ${PREFECT_SERVER_SA} \
			--image prefecthq/prefect:3-latest \
			--allow-unauthenticated \
			--port 4200 \
			--add-cloudsql-instances "$${conn}" \
			--set-env-vars PREFECT_API_DATABASE_CONNECTION_URL="$${prefect_db_url}" \
			--args "prefect","server","start","--host","0.0.0.0","--port","4200"'

deploy_metabase_cloudrun: push_metabase bootstrap_cloudsql_postgres ## Deploy Metabase image to Cloud Run (public) backed by Cloud SQL
	@bash -lc 'set -euo pipefail; \
		conn="$$(gcloud sql instances describe ${SQL_INSTANCE} --project ${GCP_PROJECT} --format="value(connectionName)")"; \
		startup_cmd="set -euo pipefail; curl -fsSL -o /tmp/cloud-sql-proxy https://storage.googleapis.com/cloud-sql-connectors/cloud-sql-proxy/v2.13.0/cloud-sql-proxy.linux.amd64; chmod +x /tmp/cloud-sql-proxy; /tmp/cloud-sql-proxy --address 127.0.0.1 --port 5432 $${conn} & exec /app/run_metabase.sh"; \
		gcloud run deploy ${METABASE_SERVICE} \
			--project ${GCP_PROJECT} \
			--region ${GCP_REGION} \
			--service-account ${METABASE_SA} \
			--image europe-west1-docker.pkg.dev/${GCP_PROJECT}/${DOCKER_REGISTRY}/${METABASE_IMAGE} \
			--allow-unauthenticated \
			--memory 2Gi \
			--command /bin/sh \
			--args "-c","$${startup_cmd}" \
			--port 3000 \
			--set-env-vars MB_JETTY_PORT=3000,MB_JAVA_OPTS=-Xms256m\ -Xmx1024m,MB_DB_TYPE=postgres,MB_DB_DBNAME=${METABASE_DB_NAME},MB_DB_PORT=5432,MB_DB_USER=${METABASE_DB_USER},MB_DB_HOST=127.0.0.1 \
			--set-secrets MB_DB_PASS=${METABASE_DB_SECRET}:latest'

print_cloudrun_urls: ## Print public URLs for Prefect server and Metabase
	@bash -lc 'set -euo pipefail; \
		prefect_url="$$(gcloud run services describe ${PREFECT_SERVER_SERVICE} --project ${GCP_PROJECT} --region ${GCP_REGION} --format="value(status.url)")"; \
		metabase_url="$$(gcloud run services describe ${METABASE_SERVICE} --project ${GCP_PROJECT} --region ${GCP_REGION} --format="value(status.url)")"; \
		echo "PREFECT_URL=$$prefect_url"; \
		echo "PREFECT_API_URL=$$prefect_url/api"; \
		echo "METABASE_URL=$$metabase_url"'

cloudrun_up: deploy_prefect_server deploy_metabase_cloudrun print_cloudrun_urls ## Deploy Prefect+Metabase and print URLs
	@echo "Cloud Run deployment completed"