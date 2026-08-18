from __future__ import annotations

import os
from dataclasses import dataclass

from dotenv import load_dotenv

load_dotenv()


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

    # 0.0.0.0 works for both local dev and Cloud Run (which refuses anything
    # bound only to 127.0.0.1). Cloud Run injects PORT itself at runtime, so
    # that takes precedence over GATEWAY_PORT when both are present.
    gateway_host: str = os.environ.get("GATEWAY_HOST", "0.0.0.0")
    gateway_port: int = int(os.environ.get("PORT", os.environ.get("GATEWAY_PORT", "8080")))

    # The URL the outside world reaches this server at -- distinct from
    # gateway_host/port above, which is only what the process binds to
    # locally (0.0.0.0 is not a usable public address). Only needed once
    # AUTH_MODE=okta; defaults to a localhost guess that's fine for local
    # testing but must be set to the real Cloud Run URL once deployed.
    public_url: str = os.environ.get("PUBLIC_URL", "http://127.0.0.1:8080")


settings = Settings()
