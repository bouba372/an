import json
from os import getenv
import subprocess
import tempfile
from pathlib import Path

from dotenv import load_dotenv
from google.api_core.exceptions import NotFound
from google.cloud import bigquery
from prefect import flow, get_run_logger, task
from prefect.artifacts import create_markdown_artifact

from lib.config import ProjectConfig, get_config


load_dotenv()


REQUIRED_RAW_TABLES: tuple[str, ...] = (
    "acteurs",
    "mandats",
    "organes",
    "interventions",
    "points_seance",
    "comptes_rendus",
    "scrutins",
    "questions_ecrites",
    "questions_ecrites_renouvellements",
    "scrutin_votes_individuels",
    "scrutin_groupes_votes",
    "documents",
    "dossiers_parlementaires",
    "dossier_actes_legislatifs",
    "amendements",
)


def _profiles_yml_content(
    config: ProjectConfig, target: str, keyfile_path: Path
) -> str:
    return (
        "dbt_parlemAn:\n"
        f"  target: {target}\n"
        "  outputs:\n"
        f"    {target}:\n"
        "      type: bigquery\n"
        "      method: service-account\n"
        f"      project: {config.gcp_project}\n"
        f"      dataset: {config.bq_dataset}\n"
        "      threads: 4\n"
        "      timeout_seconds: 300\n"
        "      location: EU\n"
        f"      keyfile: {keyfile_path}\n"
    )


def _get_missing_source_tables(config: ProjectConfig) -> list[str]:
    client = bigquery.Client.from_service_account_info(
        config.service_account_info,
        project=config.gcp_project,
    )

    missing_tables: list[str] = []
    for table_name in REQUIRED_RAW_TABLES:
        table_id = f"{config.gcp_project}.{config.bq_dataset}.{table_name}"
        try:
            client.get_table(table_id)
        except NotFound:
            missing_tables.append(table_name)

    return missing_tables


@task
def run_dbt_build(
    config: ProjectConfig,
    target: str = "prod",
    select: str | None = None,
    full_refresh: bool = False,
) -> None:
    logger = get_run_logger()

    missing_tables = _get_missing_source_tables(config)
    if missing_tables:
        missing_table_list = ", ".join(sorted(missing_tables))
        logger.error(
            "Missing required raw source tables in %s.%s: %s",
            config.gcp_project,
            config.bq_dataset,
            missing_table_list,
        )
        raise RuntimeError(
            "Missing required BigQuery raw source tables before dbt build: "
            f"{missing_table_list}. "
            "Run the ingestion deployments first (deputes, debats, scrutins, "
            "dossiers_legislatifs, questions_ecrites, amendements)."
        )

    project_dir = Path(__file__).resolve().parents[1] / "dbt_parlemAn"

    with tempfile.TemporaryDirectory(prefix="dbt_profiles_") as profiles_dir:
        keyfile_path = Path(profiles_dir) / "service_account.json"
        profiles_path = Path(profiles_dir) / "profiles.yml"

        keyfile_path.write_text(
            json.dumps(config.service_account_info), encoding="utf-8"
        )

        profiles_path.write_text(
            _profiles_yml_content(config, target, keyfile_path),
            encoding="utf-8",
        )

        command = f"dbt build --project-dir {project_dir} --profiles-dir {profiles_dir} --target {target}"

        if select:
            command += f" --select {select}"
        if full_refresh:
            command += " --full-refresh"

        logger.info("Running command: %s", command)
        result = subprocess.run(
            command,
            cwd=project_dir,
            capture_output=True,
            text=True,
            check=False,
            shell=True,
            executable=getenv("SHELL", "/bin/bash"),
        )

    if result.stdout:
        logger.info("dbt stdout:\n%s", result.stdout)
    if result.stderr:
        logger.warning("dbt stderr:\n%s", result.stderr)

    if result.returncode != 0:
        raise RuntimeError(f"dbt build failed with exit code {result.returncode}")

    create_markdown_artifact(
        key="dbt-build-summary",
        markdown=(
            f"### dbt build succeeded\n"
            f"- target: `{target}`\n"
            f"- project: `{config.gcp_project}`\n"
            f"- dataset: `{config.bq_dataset}`\n"
            f"- select: `{select or 'all'}`\n"
            f"- full_refresh: `{full_refresh}`"
        ),
        description="dbt build execution summary",
    )


@flow
def dbt_build_flow(
    target: str = "prod",
    select: str | None = None,
    full_refresh: bool = False,
) -> None:
    config = get_config()
    run_dbt_build(
        config=config, target=target, select=select, full_refresh=full_refresh
    )


if __name__ == "__main__":
    dbt_build_flow()
