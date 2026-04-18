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

## Installation

1. Install [uv](https://docs.astral.sh/uv/getting-started/installation/)
2. *(Optional)* Install [direnv](https://direnv.net/docs/installation.html) for automatic environment loading:
   ```bash
   # macOS
   brew install direnv

   # Linux
   curl -sfL https://direnv.net/install.sh | bash
   ```
   Then allow the project directory:
   ```bash
   direnv allow
   ```
3. Sync dependencies
4. Install pre-commit hooks *(optional but recommended)*

```bash
uv sync
uv run pre-commit install
uv run pre-commit autoupdate
```

## Configuration

All configuration is centralized in `.env`. Copy from the template and customize as needed:

```bash
cp .env.example .env
```

Edit `.env` to override defaults:
- `GCP_PROJECT`: BigQuery project ID (default: parleman-491810)
- `BQ_DATASET`: BigQuery dataset name (default: ParlemAN_tests)
- `DATA_URL`: Assembly open data archive URL (defaults to latest)
- `GOOGLE_APPLICATION_CREDENTIALS`: Path to GCP service account JSON

### Environment Loading

**Python**: Configuration loads from `.env` via `python-dotenv` in runtime modules

**Shell**: If [direnv](https://direnv.net/) is installed, variables auto-load when entering the directory via `.envrc`

> Never commit `.env` or `.secrets/` to git. Use `.env.example` as a template.

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

## Run Pipeline

The orchestration layer uses Airflow DAGs in [dags/parleman.py](dags/parleman.py).

Build and start the local Airflow stack:

```bash
docker compose -f infra/docker-compose.yml up -d --build airflow-postgres airflow-init airflow-webserver airflow-scheduler
```

Airflow UI: http://localhost:8080

Available DAGs:
- `deputes`
- `debats`
- `scrutins`
- `dossiers_legislatifs`
- `amendements`
- `questions_ecrites`
- `dbt_build`

## Streamlit (local)

Requires: Docker + Docker Compose.

1. Ensure your `.env` includes `SERVICE_ACCOUNT_INFO` pointing to a readable service account JSON.

2. Start Streamlit:

```bash
docker compose -f infra/docker-compose.yml up -d --build streamlit
```

Access:
- Streamlit: http://localhost:8501

The dashboard reads from the BigQuery dataset configured in `.env` and uses the service account referenced by `SERVICE_ACCOUNT_INFO`.

Stop Streamlit:

```bash
docker compose -f infra/docker-compose.yml stop streamlit
```

## Airflow Deployment

Build the Airflow image used by the local stack or by a managed runtime:

```bash
make build_airflow_image
```

The image is defined in [infra/airflow/Dockerfile](infra/airflow/Dockerfile) and keeps the repository code on `PYTHONPATH` so the DAGs can import the existing parsing modules directly.


### Using the starter dbt parlemAn project

Try running the following commands:
- pip install dbt-bigquery
- dbt debug
- dbt run
- dbt test

## Security

- **Never commit real `.env` files**: Use `.env.example` as a template for team distribution
- **Never commit `.secrets/` directory**: Contains sensitive GCP service account keys
- **`.envrc` is safe to commit**: It's configuration for loading `.env`, not secrets themselves
- Rotate service account keys regularly (keep max 2 keys per service account)
- Use minimal IAM roles (`bigquery.jobUser` + `bigquery.dataEditor`) for service accounts
