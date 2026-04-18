ifneq (,$(wildcard .env))
include .env
export
endif

AIRFLOW_SA ?= ${SA_WORKER_NAME}@${GCP_PROJECT}.iam.gserviceaccount.com
AIRFLOW_RUN_SERVICE ?= parleman-airflow-web
AIRFLOW_RUN_MEMORY ?= 2Gi
AIRFLOW_RUN_CPU ?= 1
AIRFLOW_SCHEDULER_RUN_SERVICE ?= parleman-airflow-scheduler
AIRFLOW_SCHEDULER_RUN_MEMORY ?= 2Gi
AIRFLOW_SCHEDULER_RUN_CPU ?= 1
STREAMLIT_IMAGE ?= parleman-streamlit
STREAMLIT_SERVICE ?= parleman-streamlit
STREAMLIT_PORT ?= 8501

.PHONY: help
help: ## Show available make targets
	@echo "Available targets:"; \
	awk 'BEGIN {FS = ":.*## "} /^[a-zA-Z0-9_.-]+:.*## / {printf "  %-34s %s\n", $$1, $$2}' Makefile

build_streamlit_image: ## Build image for Streamlit (Linux/amd64 platform)
	@echo "Building the image for GCP..."
	docker build --platform linux/amd64 -t europe-west1-docker.pkg.dev/${GCP_PROJECT}/${DOCKER_REGISTRY}/${STREAMLIT_IMAGE} -f infra/streamlit/Dockerfile .

push_streamlit_image: build_streamlit_image ## Build and push Streamlit image to Artifact Registry
	docker push europe-west1-docker.pkg.dev/${GCP_PROJECT}/${DOCKER_REGISTRY}/${STREAMLIT_IMAGE}


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

streamlit_up: ## Start local Streamlit app
	docker compose -f ${LOCAL_COMPOSE_FILE} up -d --build streamlit

streamlit_down: ## Stop local Streamlit app
	docker compose -f ${LOCAL_COMPOSE_FILE} stop streamlit

streamlit_logs: ## Follow local Streamlit logs
	docker compose -f ${LOCAL_COMPOSE_FILE} logs -f streamlit

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

airflow_run_deploy: push_airflow_image ## Deploy Airflow webserver to Cloud Run and print URL
	@bash -lc 'set -euo pipefail; \
		: "$${GCP_PROJECT:?Set GCP_PROJECT in .env}"; \
		: "$${GCP_REGION:?Set GCP_REGION in .env}"; \
		: "$${AIRFLOW_SA:?Set AIRFLOW_SA in .env}"; \
		: "$${AIRFLOW_DB_USER:?Set AIRFLOW_DB_USER in .env}"; \
		: "$${AIRFLOW_DB_NAME:?Set AIRFLOW_DB_NAME in .env}"; \
		: "$${AIRFLOW_DB_SECRET:?Set AIRFLOW_DB_SECRET in .env}"; \
		: "$${AIRFLOW_WEBSERVER_SECRET_KEY:?Set AIRFLOW_WEBSERVER_SECRET_KEY in .env}"; \
		conn="$$(gcloud sql instances describe ${SQL_INSTANCE} --project "$${GCP_PROJECT}" --format="value(connectionName)")"; \
		db_password="$$(gcloud secrets versions access latest --project "$${GCP_PROJECT}" --secret="${AIRFLOW_DB_SECRET}")"; \
		db_password_escaped="$$(AIRFLOW_DB_PASSWORD="$$db_password" python3 -c "import os, urllib.parse; print(urllib.parse.quote(os.environ[\"AIRFLOW_DB_PASSWORD\"], safe=\"\"))")"; \
		sql_alchemy_conn="postgresql+psycopg2://${AIRFLOW_DB_USER}:$${db_password_escaped}@/${AIRFLOW_DB_NAME}?host=/cloudsql/$${conn}"; \
		image="${GCP_REGION}-docker.pkg.dev/${GCP_PROJECT}/${DOCKER_REGISTRY}/${AIRFLOW_IMAGE}"; \
		startup_cmd="set -euo pipefail; airflow db migrate; airflow users create --username admin --password admin --firstname Admin --lastname User --role Admin --email admin@example.com || true; airflow dags reserialize; exec airflow webserver --hostname 0.0.0.0 --port \"$${PORT:-8080}\""; \
		gcloud run deploy ${AIRFLOW_RUN_SERVICE} \
			--project "$${GCP_PROJECT}" \
			--region "$${GCP_REGION}" \
			--image "$$image" \
			--service-account "$${AIRFLOW_SA}" \
			--allow-unauthenticated \
			--port 8080 \
			--memory ${AIRFLOW_RUN_MEMORY} \
			--cpu ${AIRFLOW_RUN_CPU} \
			--add-cloudsql-instances "$${conn}" \
			--set-env-vars AIRFLOW__CORE__LOAD_EXAMPLES=False,AIRFLOW__CORE__EXECUTOR=LocalExecutor,AIRFLOW__CORE__DAGS_FOLDER=/opt/airflow/dags,AIRFLOW__CORE__STORE_SERIALIZED_DAGS=False,AIRFLOW__WEBSERVER__EXPOSE_CONFIG=False,AIRFLOW__WEBSERVER__ENABLE_PROXY_FIX=True,AIRFLOW__WEBSERVER__SECRET_KEY="$${AIRFLOW_WEBSERVER_SECRET_KEY}",AIRFLOW__DATABASE__SQL_ALCHEMY_CONN="$$sql_alchemy_conn" \
			--command /bin/bash \
			--args -lc,"$$startup_cmd"; \
		project_number="$$(gcloud projects describe "$${GCP_PROJECT}" --format="value(projectNumber)")"; \
		canonical_url="https://${AIRFLOW_RUN_SERVICE}-$${project_number}.${GCP_REGION}.run.app"; \
		url="$$(gcloud run services describe ${AIRFLOW_RUN_SERVICE} --project "$${GCP_PROJECT}" --region "$${GCP_REGION}" --format="value(status.url)")"; \
		echo "AIRFLOW_RUN_URL=$$url"; \
		echo "AIRFLOW_RUN_URL_CANONICAL=$$canonical_url"'

airflow_run_scheduler_deploy: push_airflow_image ## Deploy Airflow scheduler companion service to Cloud Run
	@bash -lc 'set -euo pipefail; \
		: "$${GCP_PROJECT:?Set GCP_PROJECT in .env}"; \
		: "$${GCP_REGION:?Set GCP_REGION in .env}"; \
		: "$${AIRFLOW_SA:?Set AIRFLOW_SA in .env}"; \
		: "$${AIRFLOW_DB_USER:?Set AIRFLOW_DB_USER in .env}"; \
		: "$${AIRFLOW_DB_NAME:?Set AIRFLOW_DB_NAME in .env}"; \
		: "$${AIRFLOW_DB_SECRET:?Set AIRFLOW_DB_SECRET in .env}"; \
		conn="$$(gcloud sql instances describe ${SQL_INSTANCE} --project "$${GCP_PROJECT}" --format="value(connectionName)")"; \
		db_password="$$(gcloud secrets versions access latest --project "$${GCP_PROJECT}" --secret="${AIRFLOW_DB_SECRET}")"; \
		db_password_escaped="$$(AIRFLOW_DB_PASSWORD="$$db_password" python3 -c "import os, urllib.parse; print(urllib.parse.quote(os.environ[\"AIRFLOW_DB_PASSWORD\"], safe=\"\"))")"; \
		sql_alchemy_conn="postgresql+psycopg2://${AIRFLOW_DB_USER}:$${db_password_escaped}@/${AIRFLOW_DB_NAME}?host=/cloudsql/$${conn}"; \
		image="${GCP_REGION}-docker.pkg.dev/${GCP_PROJECT}/${DOCKER_REGISTRY}/${AIRFLOW_IMAGE}"; \
		scheduler_cmd="set -euo pipefail; airflow db migrate; airflow scheduler & exec python -m http.server \"$${PORT:-8080}\""; \
		gcloud run deploy ${AIRFLOW_SCHEDULER_RUN_SERVICE} \
			--project "$${GCP_PROJECT}" \
			--region "$${GCP_REGION}" \
			--image "$$image" \
			--service-account "$${AIRFLOW_SA}" \
			--no-allow-unauthenticated \
			--port 8080 \
			--memory ${AIRFLOW_SCHEDULER_RUN_MEMORY} \
			--cpu ${AIRFLOW_SCHEDULER_RUN_CPU} \
			--min-instances 1 \
			--no-cpu-throttling \
			--add-cloudsql-instances "$${conn}" \
			--set-env-vars AIRFLOW__CORE__LOAD_EXAMPLES=False,AIRFLOW__CORE__EXECUTOR=LocalExecutor,AIRFLOW__CORE__DAGS_FOLDER=/opt/airflow/dags,AIRFLOW__CORE__STORE_SERIALIZED_DAGS=False,AIRFLOW__DATABASE__SQL_ALCHEMY_CONN="$$sql_alchemy_conn" \
			--command /bin/bash \
			--args -lc,"$$scheduler_cmd"; \
		echo "AIRFLOW_SCHEDULER_RUN_SERVICE=${AIRFLOW_SCHEDULER_RUN_SERVICE}"'

airflow_run_url: ## Print Cloud Run URL for Airflow webserver
	@bash -lc 'set -euo pipefail; \
		project_number="$$(gcloud projects describe "$${GCP_PROJECT}" --format="value(projectNumber)")"; \
		canonical_url="https://${AIRFLOW_RUN_SERVICE}-$${project_number}.${GCP_REGION}.run.app"; \
		url="$$(gcloud run services describe ${AIRFLOW_RUN_SERVICE} --project "$${GCP_PROJECT}" --region "$${GCP_REGION}" --format="value(status.url)")"; \
		echo "AIRFLOW_RUN_URL=$$url"; \
		echo "AIRFLOW_RUN_URL_CANONICAL=$$canonical_url"'