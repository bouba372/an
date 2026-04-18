from collections.abc import Mapping
import logging
from typing import Sequence

from dotenv import load_dotenv

from lib.bq_utils import load_all_tables
from lib.bq_utils.models import BigQueryRow
from lib.config import ProjectConfig, get_config
from lib.dossiers_legislatifs import (
    DOSSIERS_LEGISLATIFS_SCHEMAS,
    DossiersParseResult,
    parse_dossiers_legislatifs,
)
from lib.extract import fetch_zip_file


load_dotenv()

logger = logging.getLogger(__name__)


def fetch_zip(url: str) -> bytes:
    logger.info(f"Downloading {url}")
    content = fetch_zip_file(url)
    logger.info(f"Downloaded {len(content):,} bytes")
    return content


def parse_dossiers_table(zip_bytes: bytes) -> DossiersParseResult:
    result = parse_dossiers_legislatifs(zip_bytes)
    logger.info(f"Parsed {len(result.documents)} documents")
    logger.info(f"Parsed {len(result.dossiers_parlementaires)} dossiers parlementaires")
    logger.info(f"Parsed {len(result.dossier_actes_legislatifs)} actes legislatifs")
    return result


def load_to_bigquery(
    dossiers_result: DossiersParseResult, config: ProjectConfig
) -> None:
    table_payloads: Mapping[str, Sequence[BigQueryRow]] = {
        "documents": dossiers_result.documents,
        "dossiers_parlementaires": dossiers_result.dossiers_parlementaires,
        "dossier_actes_legislatifs": dossiers_result.dossier_actes_legislatifs,
    }

    loaded_rows = load_all_tables(
        table_rows=table_payloads,
        schemas=DOSSIERS_LEGISLATIFS_SCHEMAS,
        config=config,
    )

    logger.info(
        "Loaded rows summary: %s",
        {table_name: loaded_rows[table_name] for table_name in table_payloads},
    )


def dossiers_legislatifs_flow() -> None:
    config = get_config()
    zip_bytes = fetch_zip(config.dossiers_legislatifs_url)
    dossiers_result = parse_dossiers_table(zip_bytes)
    load_to_bigquery(dossiers_result, config)


if __name__ == "__main__":
    dossiers_legislatifs_flow()
