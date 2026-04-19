from __future__ import annotations

from collections.abc import Callable
from datetime import datetime
from zoneinfo import ZoneInfo

from airflow import DAG
from airflow.operators.python import PythonOperator

from flows.run_dbt_build import dbt_build_flow
from flows.upload_amendements_bq import amendements_flow
from flows.upload_debats_bq import debat_flow
from flows.upload_deputes_bq import an_deputes_flow
from flows.upload_dossiers_legislatifs_bq import dossiers_legislatifs_flow
from flows.upload_questions_ecrites_bq import questions_ecrites_flow
from flows.upload_scrutins_bq import scrutin_flow
from flows.train_text_classification import text_classification_train_dag


PARIS_TZ = ZoneInfo("Europe/Paris")
START_DATE = datetime(2026, 1, 1, tzinfo=PARIS_TZ)


def _single_task_dag(
    dag_id: str,
    python_callable: Callable[[], None],
    schedule: str | None,
    task_id: str = "run_pipeline",
) -> DAG:
    dag = DAG(
        dag_id=dag_id,
        start_date=START_DATE,
        schedule=schedule,
        catchup=False,
        tags=["parleman"],
        default_args={"owner": "parleman", "retries": 1},
        description=f"ParlemAN {dag_id} pipeline",
    )

    with dag:
        PythonOperator(
            task_id=task_id,
            python_callable=python_callable,
        )

    return dag


deputes_dag = _single_task_dag("deputes", an_deputes_flow, "15 14 * * 1-5")
debats_dag = _single_task_dag("debats", debat_flow, "15 14 * * 1-5")
scrutins_dag = _single_task_dag("scrutins", scrutin_flow, "15 14 * * 1-5")
dossiers_legislatifs_dag = _single_task_dag(
    "dossiers_legislatifs",
    dossiers_legislatifs_flow,
    "15 14 * * 1-5",
)
amendements_dag = _single_task_dag(
    "amendements",
    amendements_flow,
    "15 14 * * 1-5",
)
questions_ecrites_dag = _single_task_dag(
    "questions_ecrites",
    questions_ecrites_flow,
    "15 14 * * 1-5",
)
dbt_build_dag = _single_task_dag("dbt_build", dbt_build_flow, "45 14 * * 1-5")
