import logging
import os

from dotenv import load_dotenv

from lib.amendements.parsing import parse_amendements
from lib.bq_utils import load_all_tables
from lib.config import ProjectConfig, get_config
from lib.amendements import (
    AMENDEMENTS_SCHEMAS,
)
from lib.extract import fetch_zip_file_to_temp


load_dotenv()

logger = logging.getLogger(__name__)


def fetch_zip_to_file(url: str) -> str:
    logger.info(f"Downloading {url}")
    file_path = fetch_zip_file_to_temp(url)
    logger.info(f"Downloaded archive to {file_path}")
    return file_path


def cleanup_temp_file(zip_file_path: str) -> None:
    if os.path.exists(zip_file_path):
        os.remove(zip_file_path)
        logger.info("Deleted temporary file %s", zip_file_path)


def parse_and_load_amendements(
    zip_file_path: str,
    config: ProjectConfig,
) -> None:
    table_names = {
        "amendements",
        "amendement_signataires",
        "amendement_cosignataires",
    }

    try:
        amendements = parse_amendements(zip_file_path)
        table_rows = {
            "amendements": amendements.amendements,
            "amendement_signataires": amendements.signataires,
            "amendement_cosignataires": amendements.cosignataires,
        }
        loaded_rows = load_all_tables(
            table_rows=table_rows,
            schemas=AMENDEMENTS_SCHEMAS,
            config=config,
        )
        logger.info(
            "Loaded rows summary: %s",
            {table_name: loaded_rows[table_name] for table_name in table_names},
        )
    finally:
        cleanup_temp_file(zip_file_path)

    logger.info("Finished loading amendements")


def amendements_flow() -> None:
    config = get_config()
    zip_file_path = fetch_zip_to_file(config.amendements_url)
    parse_and_load_amendements(zip_file_path, config)


if __name__ == "__main__":
    amendements_flow()
