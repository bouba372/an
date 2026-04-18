FROM apache/airflow:2.10.4-python3.12

USER root
RUN apt-get update && apt-get install -y --no-install-recommends git \
    && rm -rf /var/lib/apt/lists/*

USER airflow
COPY infra/airflow/requirements-airflow.txt /requirements-airflow.txt
RUN pip install --no-input --no-cache-dir -r /requirements-airflow.txt

WORKDIR /opt/airflow
COPY dags ./dags
COPY flows ./flows
COPY lib ./lib
COPY dbt_parlemAn ./dbt_parlemAn
COPY README.md ./README.md
COPY pyproject.toml ./pyproject.toml

ENV PYTHONPATH=/opt/airflow
