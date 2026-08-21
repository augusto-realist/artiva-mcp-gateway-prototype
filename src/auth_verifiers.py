from __future__ import annotations

import jwt
from mcp.server.auth.provider import AccessToken, TokenVerifier

from .config import settings

_jwks_client: jwt.PyJWKClient | None = None


def _get_jwks_client() -> jwt.PyJWKClient:
    global _jwks_client
    if _jwks_client is None:
        if not settings.okta_issuer:
            raise RuntimeError("OKTA_ISSUER is not set")
        _jwks_client = jwt.PyJWKClient(f"{settings.okta_issuer}/v1/keys")
    return _jwks_client


def verify_okta_id_token(token: str) -> AccessToken | None:
    """Verifies a raw string as an Okta-issued ID token, returning an AccessToken
    if valid. Shared by OktaTokenVerifier (AUTH_MODE=okta -- the token arrives
    as a bearer header, issued directly to Claude by Okta) and
    OktaBrokerProvider.load_access_token (AUTH_MODE=okta_broker -- same kind of
    token, but this gateway obtained it itself via oauth_broker.py's own Okta
    exchange, then handed it to Claude as an opaque "access token"). Either way
    the token itself is a real Okta ID token, so verification is identical.
    """
    try:
        signing_key = _get_jwks_client().get_signing_key_from_jwt(token)
        claims = jwt.decode(
            token,
            signing_key.key,
            algorithms=["RS256"],
            audience=settings.okta_audience or settings.okta_client_id,
            issuer=settings.okta_issuer,
        )
    except jwt.PyJWTError:
        return None

    groups = claims.get(settings.okta_groups_claim, [])
    return AccessToken(
        token=token,
        client_id=settings.okta_client_id or "okta",
        scopes=["bigquery"],
        expires_at=claims.get("exp"),
        subject=claims.get("sub"),
        claims={
            "email": claims.get("email"),
            "groups": groups,
            # STS needs the raw token, not just the parsed claims -- see federation.py.
            "okta_id_token": token,
        },
    )


class OktaTokenVerifier(TokenVerifier):
    """Verifies a bearer token as an Okta-issued ID token.

    This follows the MCP Resource-Server pattern: Claude discovers Okta as
    the authorization server from this server's Protected Resource Metadata
    and completes OAuth directly against Okta, then sends the resulting
    token straight through on every call. This gateway never runs its own
    /authorize or /callback -- it only ever verifies a token Okta already
    issued, and reads the groups claim off it.

    Used for AUTH_MODE=okta. For AUTH_MODE=okta_broker, see oauth_broker.py --
    that mode uses verify_okta_id_token directly instead, since the gateway
    itself is the OAuthAuthorizationServerProvider there, not just a verifier.
    """

    async def verify_token(self, token: str) -> AccessToken | None:
        return verify_okta_id_token(token)
