from collections.abc import Mapping
import logging
from typing import Sequence

from dotenv import load_dotenv
from lib.bq_utils import load_all_tables
from lib.bq_utils.models import BigQueryRow
from lib.config import ProjectConfig, get_config
from lib.debat import DebatParseResult, parse_debats_files
from lib.debat.bq_schemas import DEBATS_SCHEMAS
from lib.extract import extract_file_contents, fetch_zip_file


load_dotenv()

logger = logging.getLogger(__name__)


def fetch_debat_data(debat_url: str) -> bytes:
    return fetch_zip_file(debat_url)


def extract_debat_data(debat_archive: bytes) -> list[str]:
    return extract_file_contents(debat_archive)


def parse_debat_contents(debat_contents: list[str]) -> DebatParseResult:
    return parse_debats_files(debat_contents)


def upload_to_bigquery(parsed_debats: DebatParseResult, config: ProjectConfig) -> None:
    table_payloads: Mapping[str, Sequence[BigQueryRow]] = {
        "comptes_rendus": parsed_debats.comptes_rendus,
        "points_seance": parsed_debats.points,
        "interventions": parsed_debats.interventions,
    }

    loaded_rows = load_all_tables(
        table_rows=table_payloads,
        schemas=DEBATS_SCHEMAS,
        config=config,
    )

    logger.info(
        "Loaded rows summary: %s",
        {table_name: loaded_rows[table_name] for table_name in table_payloads},
    )


def debat_flow() -> None:
    config = get_config()
    debat_archive = fetch_debat_data(debat_url=config.debat_url)
    debat_contents = extract_debat_data(debat_archive)
    parsed_debats = parse_debat_contents(debat_contents)
    upload_to_bigquery(parsed_debats, config)


if __name__ == "__main__":
    debat_flow()
