from __future__ import annotations

from mcp.server.auth.middleware.auth_context import get_access_token
from mcp.server.auth.settings import AuthSettings
from mcp.server.mcpserver import MCPServer

from . import bigquery_tools, federation
from .auth_verifiers import OktaTokenVerifier
from .config import settings

_server_kwargs: dict = {}
if settings.auth_mode == "okta":
    _server_kwargs["token_verifier"] = OktaTokenVerifier()
    _server_kwargs["auth"] = AuthSettings(
        issuer_url=settings.okta_issuer,
        resource_server_url=f"http://{settings.gateway_host}:{settings.gateway_port}",
    )

mcp = MCPServer(
    name="artiva-bigquery-gateway",
    instructions=(
        "Query Artiva's BigQuery datasets. Access is enforced per-user via "
        "Okta group membership federated through Google Cloud Workforce "
        "Identity Federation -- this server never decides who can see what; "
        "BigQuery IAM does, at query time."
    ),
    **_server_kwargs,
)


async def _current_google_token() -> str | None:
    """The Google access token to query BigQuery with, for whoever is making
    the current MCP request -- or None in local dev mode, which falls back
    to the developer's own gcloud credentials (see bigquery_tools.py)."""
    access_token = get_access_token()
    if access_token is None or not access_token.claims:
        return None

    okta_id_token = access_token.claims.get("okta_id_token")
    if okta_id_token is None:
        return None

    return await federation.exchange_okta_token_for_google_token(okta_id_token)


@mcp.tool()
async def list_datasets() -> list[str]:
    """List BigQuery datasets visible to the current user."""
    return bigquery_tools.list_datasets(await _current_google_token())


@mcp.tool()
async def list_tables(dataset_id: str) -> list[str]:
    """List tables within a BigQuery dataset visible to the current user."""
    return bigquery_tools.list_tables(dataset_id, await _current_google_token())


@mcp.tool()
async def query(sql: str) -> list[dict]:
    """Run a read query against BigQuery, as the current user. Results are
    truncated to BQ_ROW_LIMIT rows."""
    return bigquery_tools.run_query(sql, await _current_google_token())


app = mcp.streamable_http_app()
