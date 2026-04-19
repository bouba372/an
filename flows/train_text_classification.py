"""DAG for text classification model training."""

from datetime import datetime
from zoneinfo import ZoneInfo

from airflow import DAG
from airflow.operators.python import PythonOperator

from mlops.training import train_flow

PARIS_TZ = ZoneInfo("Europe/Paris")
START_DATE = datetime(2026, 1, 1, tzinfo=PARIS_TZ)

text_classification_train_dag = DAG(
    dag_id="text_classification_train",
    start_date=START_DATE,
    schedule="45 14 * * 0",  # Weekly on Sundays
    catchup=False,
    tags=["parleman", "mlops"],
    default_args={"owner": "parleman", "retries": 1},
    description="Train text classification model on parliamentary interventions",
)

with text_classification_train_dag:
    train_task = PythonOperator(
        task_id="train_model",
        python_callable=train_flow,
    )
