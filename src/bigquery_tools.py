from __future__ import annotations

from google.cloud import bigquery
from google.oauth2.credentials import Credentials as OAuthCredentials

from .config import settings


def _client_for_token(google_access_token: str | None) -> bigquery.Client:
    """Build a BigQuery client scoped to one federated user's token.

    In local dev mode (no token), falls back to the developer's own
    `gcloud auth application-default login` credentials, so the MCP/BigQuery
    plumbing can be tested before Okta/WIF exist for real.
    """
    if google_access_token is None:
        return bigquery.Client(project=settings.bq_project_id)
    credentials = OAuthCredentials(token=google_access_token)
    return bigquery.Client(project=settings.bq_project_id, credentials=credentials)


def list_datasets(google_access_token: str | None) -> list[str]:
    client = _client_for_token(google_access_token)
    return [dataset.dataset_id for dataset in client.list_datasets()]


def list_tables(dataset_id: str, google_access_token: str | None) -> list[str]:
    client = _client_for_token(google_access_token)
    return [table.table_id for table in client.list_tables(dataset_id)]


def run_query(sql: str, google_access_token: str | None) -> list[dict]:
    client = _client_for_token(google_access_token)
    job_config = bigquery.QueryJobConfig(maximum_bytes_billed=settings.bq_max_bytes_billed)
    job = client.query(sql, job_config=job_config)
    rows = job.result(max_results=settings.bq_row_limit)
    return [dict(row.items()) for row in rows]
