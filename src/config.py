from __future__ import annotations

import os
from dataclasses import dataclass

from dotenv import load_dotenv

load_dotenv()


def _bool(name: str, default: bool) -> bool:
    value = os.environ.get(name)
    if value is None:
        return default
    return value.strip().lower() in ("1", "true", "yes", "on")


@dataclass(frozen=True)
class Settings:
    # "local": no auth, BigQuery via the developer's own `gcloud auth
    #   application-default login` credentials. Works today, no Artiva inputs needed.
    # "okta": real Resource-Server mode -- verifies Okta-issued bearer tokens
    #   and performs the WIF exchange per request. Needs every value below.
    auth_mode: str = os.environ.get("AUTH_MODE", "local")

    # Okta -- see Implementation Plan Phase 1 "Need from Artiva"
    okta_issuer: str | None = os.environ.get("OKTA_ISSUER")
    okta_client_id: str | None = os.environ.get("OKTA_CLIENT_ID")
    okta_audience: str | None = os.environ.get("OKTA_AUDIENCE")
    okta_groups_claim: str = os.environ.get("OKTA_GROUPS_CLAIM", "groups")

    # Workforce Identity Federation -- Implementation Plan Phase 1.6
    gcp_workforce_pool_id: str | None = os.environ.get("GCP_WORKFORCE_POOL_ID")
    gcp_workforce_provider_id: str | None = os.environ.get("GCP_WORKFORCE_PROVIDER_ID")
    gcp_billing_project: str | None = os.environ.get("GCP_BILLING_PROJECT")

    # BigQuery
    bq_project_id: str | None = os.environ.get("BQ_PROJECT_ID")
    bq_row_limit: int = int(os.environ.get("BQ_ROW_LIMIT", "500"))

    gateway_host: str = os.environ.get("GATEWAY_HOST", "127.0.0.1")
    gateway_port: int = int(os.environ.get("GATEWAY_PORT", "8080"))


settings = Settings()
