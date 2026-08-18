from __future__ import annotations

import httpx

from .config import settings

STS_ENDPOINT = "https://sts.googleapis.com/v1/token"


class FederationError(RuntimeError):
    """Raised when the Okta -> Google STS token exchange fails."""


async def exchange_okta_token_for_google_token(okta_id_token: str) -> str:
    """The Workforce Identity Federation exchange (design doc Section 3.1).

    Trades a signed Okta ID token for a short-lived Google OAuth 2.0 access
    token scoped to the federated principal, carrying the user's Okta groups
    along with it. This step does not check permissions -- it only
    translates identity into a shape Google recognizes. BigQuery IAM is what
    actually decides access, later, when the returned token is used to query.
    """
    if not settings.gcp_workforce_pool_id or not settings.gcp_workforce_provider_id:
        raise FederationError(
            "GCP_WORKFORCE_POOL_ID / GCP_WORKFORCE_PROVIDER_ID are not set -- "
            "Workforce Identity Federation hasn't been configured yet "
            "(Implementation Plan Phase 1.6)."
        )

    audience = (
        "//iam.googleapis.com/locations/global/workforcePools/"
        f"{settings.gcp_workforce_pool_id}/providers/{settings.gcp_workforce_provider_id}"
    )
    payload = {
        "grant_type": "urn:ietf:params:oauth:grant-type:token-exchange",
        "requested_token_type": "urn:ietf:params:oauth:token-type:access_token",
        "subject_token_type": "urn:ietf:params:oauth:token-type:id_token",
        "subject_token": okta_id_token,
        "audience": audience,
        "scope": "https://www.googleapis.com/auth/cloud-platform",
    }
    if settings.gcp_billing_project:
        payload["options"] = f'{{"userProject":"{settings.gcp_billing_project}"}}'

    async with httpx.AsyncClient(timeout=10.0) as client:
        response = await client.post(STS_ENDPOINT, data=payload)

    if response.status_code != 200:
        raise FederationError(f"STS token exchange failed ({response.status_code}): {response.text}")

    return response.json()["access_token"]
