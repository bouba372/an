FROM python:3.13-slim

# Install system dependencies
RUN apt-get update && apt-get install -y \
    git \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /app

# Copy project files
COPY pyproject.toml .
COPY mlops/ mlops/
COPY lib/ lib/
COPY flows/ flows/

# Install dependencies
RUN pip install --no-cache-dir -e ".[dev]" && \
    pip install --no-cache-dir dbt-bigquery mlflow

# Expose port
EXPOSE 5000

# Start MLflow server
CMD ["mlflow", "server", "--host", "0.0.0.0", "--port", "5000", "--backend-store-uri", "sqlite:////tmp/mlflow.db"]
