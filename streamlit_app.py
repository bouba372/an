from __future__ import annotations

import pandas as pd
import streamlit as st
from google.cloud import bigquery
from google.oauth2 import service_account

from lib.config import get_config


st.set_page_config(page_title="ParlemAN Streamlit", layout="wide")


@st.cache_resource
def get_bq_client() -> tuple[bigquery.Client, str]:
    config = get_config()
    credentials = service_account.Credentials.from_service_account_info(
        config.service_account_info,
    )
    client = bigquery.Client(
        project=config.gcp_project,
        credentials=credentials,
    )
    return client, config.bq_dataset


@st.cache_data(ttl=60)
def list_tables(project_id: str, dataset_name: str) -> list[str]:
    client, _ = get_bq_client()
    sql = f"""
        SELECT table_name
        FROM `{project_id}.{dataset_name}.INFORMATION_SCHEMA.TABLES`
        WHERE table_type = 'BASE TABLE'
        ORDER BY table_name
    """
    return [row.table_name for row in client.query(sql).result()]


@st.cache_data(ttl=60)
def count_rows(project_id: str, dataset_name: str, table_name: str) -> int:
    client, _ = get_bq_client()
    sql = f"SELECT COUNT(1) AS row_count FROM `{project_id}.{dataset_name}.{table_name}`"
    row = next(iter(client.query(sql).result()))
    return int(row.row_count)


@st.cache_data(ttl=60)
def preview_table(project_id: str, dataset_name: str, table_name: str, limit: int = 20) -> pd.DataFrame:
    client, _ = get_bq_client()
    sql = f"SELECT * FROM `{project_id}.{dataset_name}.{table_name}` LIMIT {limit}"
    rows = [dict(row) for row in client.query(sql).result()]
    return pd.DataFrame(rows)


def main() -> None:
    client, dataset_name = get_bq_client()
    project_id = client.project

    st.title("ParlemAN Streamlit")
    st.caption("Exploration rapide des tables BigQuery du projet ParlemAN.")

    tables = list_tables(project_id, dataset_name)
    if not tables:
        st.warning(f"Aucune table trouvée dans {project_id}.{dataset_name}.")
        return

    sidebar = st.sidebar
    sidebar.header("Navigation")
    sidebar.write(f"Project: `{project_id}`")
    sidebar.write(f"Dataset: `{dataset_name}`")

    selected_table = sidebar.selectbox("Table", tables)

    total_tables = len(tables)
    total_rows = count_rows(project_id, dataset_name, selected_table)

    col1, col2 = st.columns(2)
    col1.metric("Tables", total_tables)
    col2.metric(f"Rows in {selected_table}", f"{total_rows:,}")

    st.subheader(f"Preview: {selected_table}")
    preview_df = preview_table(project_id, dataset_name, selected_table)
    if preview_df.empty:
        st.info("Cette table est vide.")
    else:
        st.dataframe(preview_df, use_container_width=True)

    st.subheader("Tables disponibles")
    st.write(", ".join(tables))


if __name__ == "__main__":
    main()