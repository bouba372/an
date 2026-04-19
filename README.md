# ParlemAN

Pipeline for fetching/parsing French National Assembly data, with BigQuery loading, Airflow orchestration, and Streamlit analytics.

## Project Structure

```text
config/           # Configuration templates
dags/             # Airflow DAG definitions
flows/            # Pipeline logic callable from Airflow tasks
streamlit_app.py  # Streamlit dashboard
infra/            # Docker Compose stack
lib/              # Core modules (parsing, loading, validation)
scripts/          # Utility scripts and SQL views
tests/            # Unit tests
.env              # Environment variables (do not commit with real values)
.env.example      # Template for .env
pyproject.toml    # Project metadata and dependencies
README.md         # This file
```

## Prerequisites

**Required for all deployments:**
- [uv](https://docs.astral.sh/uv/getting-started/installation/) — Python package manager
- Python 3.13+
- [gcloud CLI](https://cloud.google.com/sdk/docs/install) — Google Cloud SDK
- [Docker](https://docs.docker.com/get-docker/) + [Docker Compose](https://docs.docker.com/compose/install/)
- [Terraform](https://www.terraform.io/downloads) — For Cloud SQL provisioning

**Optional:**
- [direnv](https://direnv.net/docs/installation.html) — Auto-load `.env`
- [pre-commit](https://pre-commit.com/) — Git hooks

## Installation

1. Clone and navigate to the project directory

2. Install dependencies using uv:
   ```bash
   uv sync
   ```

3. *(Optional)* Install direnv for environment auto-loading:
   ```bash
   direnv allow
   ```

4. *(Optional)* Set up pre-commit hooks:
   ```bash
   uv run pre-commit install
   uv run pre-commit autoupdate
   ```

5. Authenticate with Google Cloud:
   ```bash
   gcloud auth application-default login
   ```

## Configuration

All configuration is centralized in `.env`. Copy from the template and customize:

```bash
cp .env.example .env
```

### Essential Variables

**Google Cloud Platform:**
- `GCP_PROJECT`: Project ID (required, e.g., `parleman-491810`)
- `GCP_REGION`: Deployment region (default: `europe-west1`)

**BigQuery:**
- `BQ_DATASET`: Dataset name (e.g., `ParlemAN_tests`)
- `GOOGLE_APPLICATION_CREDENTIALS`: Path to service account JSON (e.g., `.secrets/parleman-sa.json`)

**Service Accounts:**
- `SA_RUNNER_NAME`: Service account for pipelines (e.g., `parleman-bq-runner`)
- `SA_WORKER_NAME`: Service account for Airflow (default: `parleman-airflow-worker`)

**Airflow Production Deployment:**
- `AIRFLOW_DB_PASSWORD`: Cloud SQL password (REQUIRED for Terraform) — must be set before infrastructure provisioning
- `AIRFLOW_WEBSERVER_SECRET_KEY`: Secret for CSRF tokens

### Data Pipeline URLs

Endpoints for fetching French National Assembly data:
- `DEPUTES_URL`: Deputies endpoint
- `DEBAT_URL`: Debates endpoint
- `SCRUTINS_URL`: Voting records endpoint
- `DOSSIERS_LEGISLATIFS_URL`: Legislative dossiers endpoint
- `AMENDEMENTS_URL`: Amendments endpoint
- `QUESTIONS_ECRITES_URL`: Written questions endpoint

### See Also

For complete environment variable reference, see [.env.example](.env.example).

### Environment Loading

**Python**: Configuration loads from `.env` via `python-dotenv` in runtime modules

**Shell**: If [direnv](https://direnv.net/) is installed, variables auto-load when entering the directory via `.envrc`

> **Security**: Never commit `.env` or `.secrets/` to git. Use `.env.example` as a template.

## GCP Setup

1. Create service accounts:

For runner (runs flow code):
```bash
export GCP_PROJECT="parleman-491810"
export SA_RUNNER_NAME="parleman-bq-runner"

gcloud iam service-accounts create "$SA_RUNNER_NAME" \
  --project "$GCP_PROJECT" \
  --display-name "ParlemAN BigQuery Runner"
```

For worker (invokes jobs on Cloud Run):
```bash
export SA_WORKER_NAME="parleman-airflow-worker"

gcloud iam service-accounts create "$SA_WORKER_NAME" \
  --project "$GCP_PROJECT" \
  --display-name "ParlemAN Airflow Worker"
```

2. Grant minimal roles:

For runner:
```bash
gcloud projects add-iam-policy-binding "$GCP_PROJECT" \
  --member "serviceAccount:${SA_RUNNER_NAME}@${GCP_PROJECT}.iam.gserviceaccount.com" \
  --role "roles/bigquery.jobUser"

gcloud projects add-iam-policy-binding "$GCP_PROJECT" \
  --member "serviceAccount:${SA_RUNNER_NAME}@${GCP_PROJECT}.iam.gserviceaccount.com" \
  --role "roles/bigquery.dataEditor"
```

For worker:
```bash
gcloud projects add-iam-policy-binding "$GCP_PROJECT" \
  --member "serviceAccount:${SA_WORKER_NAME}@${GCP_PROJECT}.iam.gserviceaccount.com" \
  --role "roles/run.invoker"

gcloud projects add-iam-policy-binding "$GCP_PROJECT" \
  --member "serviceAccount:${SA_WORKER_NAME}@${GCP_PROJECT}.iam.gserviceaccount.com" \
  --role "roles/artifactregistry.reader"

gcloud projects add-iam-policy-binding "$GCP_PROJECT" \
  --member "serviceAccount:${SA_WORKER_NAME}@${GCP_PROJECT}.iam.gserviceaccount.com" \
  --role "roles/iam.serviceAccountUser"
```


3. Create local key:

```bash
mkdir -p .secrets
gcloud iam service-accounts keys create .secrets/parleman-sa.json \
  --iam-account "${SA_RUNNER_NAME}@${GCP_PROJECT}.iam.gserviceaccount.com" \
  --project "$GCP_PROJECT"
```

4. Set environment variable in `.env`:

```bash
GOOGLE_APPLICATION_CREDENTIALS=.secrets/parleman-sa.json
```

## Infrastructure Setup

Before deploying to Cloud Run, provision the infrastructure:

### 1. Initialize Terraform

```bash
make terraform_init
```

### 2. Set Database Password (Required)

```bash
# Add to .env file
AIRFLOW_DB_PASSWORD="your-secure-password-here"
```

**Important:** This password is stored in Google Secret Manager, not on disk.

### 3. Preview Infrastructure Changes

```bash
make terraform_plan
```

This creates:
- Cloud SQL PostgreSQL 16 instance
- Airflow metadata database and user
- VPC networking for secure access
- Secrets in Google Secret Manager

### 4. Provision Cloud SQL

```bash
make bootstrap_cloudsql_postgres
```

This runs Terraform apply and stores the database password in Secret Manager automatically.

## Run Pipeline

The orchestration layer uses Apache Airflow with DAGs defined in [dags/parleman.py](dags/parleman.py).

### Local Development

Start the local Airflow stack:

```bash
make airflow_up
```

This starts:
- **Webserver**: http://localhost:8080 (default credentials: admin / admin)
- **Scheduler**: Task scheduler for DAGs
- **PostgreSQL**: Local metadata database

View logs:
```bash
make airflow_logs
```

Stop the stack:
```bash
make airflow_down
```

### Cloud Run Production Deployment

**Prerequisite:** Run `make bootstrap_cloudsql_postgres` first (see Infrastructure Setup section above).

Deploy the Airflow webserver to Cloud Run:

```bash
make airflow_run_deploy
```

This:
- Builds and pushes the Airflow Docker image
- Deploys webserver service (`parleman-airflow-web`)
- Configures LocalExecutor with Cloud SQL Unix socket
- Outputs the service URL

Deploy the scheduler as a separate service:

```bash
make airflow_run_scheduler_deploy
```

The scheduler service:
- Service name: `parleman-airflow-scheduler`
- Always running (`--min-instances 1`)
- Processes queued DAG tasks
- Gets heartbeat to prevent "scheduler not running" warnings

Retrieve the webserver URL:

```bash
make airflow_run_url
```

### Available DAGs

| DAG | Purpose | Schedule |
|-----|---------|----------|
| `deputes` | Fetch French parliament deputies | 15:14 UTC, Mon-Fri |
| `debats` | Fetch parliamentary debates | 15:14 UTC, Mon-Fri |
| `scrutins` | Fetch voting records | 15:14 UTC, Mon-Fri |
| `dossiers_legislatifs` | Fetch legislative dossiers | 15:14 UTC, Mon-Fri |
| `amendements` | Fetch amendments | 15:14 UTC, Mon-Fri |
| `questions_ecrites` | Fetch written questions | 15:14 UTC, Mon-Fri |
| `dbt_build` | Run dbt transformations | 15:30 UTC, Mon-Fri |

### Executor Configuration

The stack uses **LocalExecutor** (not SequentialExecutor) for better parallelism:
- Environment variables for webserver: `AIRFLOW__CORE__EXECUTOR=LocalExecutor`
- Environment variables for scheduler: `AIRFLOW__CORE__EXECUTOR=LocalExecutor`

## Streamlit Analytics Dashboard

### Local Development

Requires: Docker + Docker Compose.

1. Ensure your `.env` includes `SERVICE_ACCOUNT_INFO` (service account JSON path):
   ```bash
   export SERVICE_ACCOUNT_INFO=".secrets/parleman-sa.json"
   ```

2. Start Streamlit locally:
   ```bash
   make streamlit_up
   ```

   Or manually:
   ```bash
   docker compose -f infra/docker-compose.yml up -d --build streamlit
   ```

3. Access the dashboard:
   - **Streamlit UI**: http://localhost:8501

The dashboard features:
- BigQuery dataset browser
- Table row counting and sampling
- Data preview with schema inspection
- All queries cached for 60 seconds

Stop Streamlit:

```bash
make streamlit_down
```

### Cloud Run Production Deployment

Build and push the Streamlit image to Google Artifact Registry:

```bash
make build_streamlit_image
make push_streamlit_image
```

The image is stored in: `europe-west1-docker.pkg.dev/{GCP_PROJECT}/parleman/streamlit:latest`

Deploy to Cloud Run:

```bash
gcloud run deploy parleman-streamlit \
  --image europe-west1-docker.pkg.dev/$GCP_PROJECT/parleman/streamlit:latest \
  --region europe-west1 \
  --memory 2Gi \
  --cpu 2 \
  --set-env-vars "GOOGLE_APPLICATION_CREDENTIALS=/var/secrets/google/key.json,GCP_PROJECT=$GCP_PROJECT,BQ_DATASET=$BQ_DATASET" \
  --service-account "$SA_RUNNER_NAME@$GCP_PROJECT.iam.gserviceaccount.com"
```

## Airflow Image Management

Build and push the Airflow image to Google Artifact Registry:

```bash
make build_airflow_image
make push_airflow_image
```

The image is defined in [infra/airflow/Dockerfile](infra/airflow/Dockerfile) and includes:
- Apache Airflow 2.10.4 base
- Project source code (flows, dags, lib, dbt_parlemAn) on `PYTHONPATH`
- Custom dependencies from `infra/airflow/requirements-airflow.txt`

This allows DAGs to import parsing modules directly without additional code changes.

### Make Targets Reference

**Infrastructure (Terraform):**
- `make terraform_init` - Initialize Terraform workspace
- `make terraform_plan` - Preview infrastructure changes
- `make terraform_apply` - Apply infrastructure to GCP
- `make bootstrap_cloudsql_postgres` - Provision Cloud SQL (runs terraform_apply)

**Docker Image Management:**
- `make build_airflow_image` - Build Airflow image (linux/amd64)
- `make push_airflow_image` - Push to Artifact Registry
- `make build_streamlit_image` - Build Streamlit image (linux/amd64)
- `make push_streamlit_image` - Push to Artifact Registry

**Local Development:**
- `make airflow_up` - Start Airflow stack
- `make airflow_down` - Stop Airflow stack
- `make airflow_logs` - Follow Airflow logs
- `make streamlit_up` - Start Streamlit locally
- `make streamlit_down` - Stop Streamlit
- `make streamlit_logs` - Follow Streamlit logs

**Cloud Run Deployment:**
- `make airflow_run_deploy` - Deploy webserver
- `make airflow_run_scheduler_deploy` - Deploy scheduler (separate service)
- `make airflow_run_url` - Print webserver URL


## dbt Transformations

The `dbt_build` DAG runs dbt transformations on staged data in BigQuery.

### Local Development

Navigate to the dbt project:

```bash
cd dbt_parlemAn
```

Install dbt-bigquery:

```bash
uv pip install dbt-bigquery
```

Run transformations:

```bash
dbt run
dbt test
```

View generated documentation:

```bash
dbt docs generate
dbt docs serve
```

### dbt Profiles

Configuration is held in `dbt_parlemAn/profiles.yml` (auto-generated from `.env`).

DAG deployment automatically updates the profile with current GCP project and dataset settings.

## MLOps: Text Classification

Classify French parliamentary interventions into topic categories.

### Quick Start

**Local Setup:**

1. Start MLflow tracking server:
   ```bash
   make mlflow_up
   ```

2. Start inference API:
   ```bash
   make inference_up
   ```

3. Train model:
   ```bash
   make mlops_train
   ```

4. Test predictions:
   ```bash
   curl -X POST http://localhost:8000/predict \
     -H "Content-Type: application/json" \
     -d '{"texts": "La politique de santé est importante"}'
   ```

### Additional Resources

For full MLOps documentation (architecture, configuration, deployment and ops), see [MLOPS.md](MLOPS.md).

## Security

- **Never commit real `.env` files**: Use `.env.example` as a template for team distribution
- **Never commit `.secrets/` directory**: Contains sensitive GCP service account keys
- **`.envrc` is safe to commit**: It's configuration for loading `.env`, not secrets themselves
- Rotate service account keys regularly (keep max 2 keys per service account)
- Use minimal IAM roles for service accounts:
  - `bigquery.jobUser` - Read/execute queries
  - `bigquery.dataEditor` - Create/modify datasets and tables
  - `run.invoker` - Invoke Cloud Run services
  - `artifactregistry.reader` - Pull container images
  - `iam.serviceAccountUser` - Use service account credentials

## Architecture

```
┌──────────────────┐
│  French Assembly │
│   Open Data API  │
└────────┬─────────┘
         │
    ┌────▼──────────────────────────────┐
    │        Airflow Orchestration      │
    │   (Cloud Run: Webserver/Scheduler)│
    └────┬──────────────────────────────┘
         │
    ┌────▼──────────────────────────────┐
    │    Airflow DAGs (7 Pipelines)     │
    │   ├─ deputes, debats, scrutins    │
    │   ├─ dossiers_legislatifs         │
    │   ├─ amendements                  │
    │   ├─ questions_ecrites            │
    │   └─ dbt_build (nightly)          │
    └────┬──────────────────────────────┘
         │
    ┌────▼──────────────────────────────┐
    │    BigQuery Staging Layer         │
    │   (Raw data tables)               │
    └────┬──────────────────────────────┘
         │
    ┌────┴───────────────────┬──────────┐
    │                        │          │
┌───▼────────────┐  ┌─────────▼──┐  ┌───▼──────┐
│  dbt Transform │  │ Text Classifi │  │Streamlit │
│  (mart tables) │  │ cation (MLOps)│  │Dashboard │
└────────────────┘  └───────┬──────┘  └──────────┘
                            │
                    ┌───────▼───────┐
                    │ Inference API │
                    │  (FastAPI)    │
                    └───────────────┘
```

## Troubleshooting

### Scheduler not running in production

Ensure the scheduler service is deployed:

```bash
make airflow_run_scheduler_deploy
```

Verify it's running:

```bash
gcloud run services list --filter="name:scheduler" --region=europe-west1
```

### DAGs not visible in UI

If DAGs don't appear, restart the webserver:

```bash
make airflow_run_deploy
```

Or check logs:

```bash
gcloud run services describe parleman-airflow-web --region=europe-west1
```

### Streamlit dashboard connection errors

Verify service account credentials in `.env`:

```bash
cat $GOOGLE_APPLICATION_CREDENTIALS | head -20
```

Test BigQuery access:

```bash
uv run python -c "from lib.config import get_bq_client; client = get_bq_client(); print(client.list_datasets())"
```

## License

See [LICENSE](LICENSE) for details.
