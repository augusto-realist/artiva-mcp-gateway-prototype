"""AUTH_MODE=okta_broker: this gateway acts as the OAuth Authorization Server
Claude talks to, instead of Claude talking to Okta directly (AUTH_MODE=okta).

Why this exists: Claude's connector always requests two Okta platform-default
scopes (interclient_access, device_sso) together, which Okta treats as
permanently mutually exclusive -- Okta rejects the request outright, before
any login screen appears. See "Claude-Okta Connector Issue - Summary & Path
Forward.md". Since *we* construct the Okta request in this mode instead of
Claude, we can just not ask for those scopes -- the same trick
scripts/_okta_login.py already uses successfully.

The flow (see OAuthAuthorizationServerProvider.authorize's own docstring in
the mcp SDK -- this is a directly SDK-supported pattern, not a hand-rolled
workaround):

    Claude --(1)--> this gateway's /authorize --(2)--> Okta's real /authorize
       ^                                                      |
       |                                                     (3) user logs in
       +---(5) redirect w/ OUR code-----+  Okta redirects to (4)
                                         |  our own /oauth/okta/callback
                                    (our code, mapped internally
                                     to the real Okta token)

Claude then redeems our code at our /token endpoint (step 6, entirely
SDK-handled) -- exchange_authorization_code below just hands back the real
Okta token we already obtained in step 4, unchanged. That's the key
simplification: this gateway never mints or signs its own token type: the
"access token" Claude ends up holding IS a real Okta ID token, so
verify_okta_id_token (auth_verifiers.py) is reused as-is for every later
tool call, and server.py's WIF exchange needs zero changes.

State is in-memory (module-level dicts) -- fine for this sandbox's single
Cloud Run instance. Would need a shared store (Redis/Firestore) before ever
running with more than one instance, since one instance could mint a code
that a different instance has to redeem.
"""

from __future__ import annotations

import base64
import hashlib
import secrets
import time

import httpx
from mcp.server.auth.provider import (
    AccessToken,
    AuthorizationCode,
    AuthorizationParams,
    AuthorizeError,
    OAuthAuthorizationServerProvider,
    RefreshToken,
    TokenError,
    construct_redirect_uri,
)
from mcp.shared.auth import OAuthClientInformationFull, OAuthToken
from starlette.requests import Request
from starlette.responses import RedirectResponse, Response

from .auth_verifiers import verify_okta_id_token
from .config import settings

OKTA_CALLBACK_PATH = "/oauth/okta/callback"
_AUTH_CODE_TTL_SECONDS = 300
_PENDING_TTL_SECONDS = 600


class OktaBrokerProvider(OAuthAuthorizationServerProvider[AuthorizationCode, RefreshToken, AccessToken]):
    def __init__(self) -> None:
        self._clients: dict[str, OAuthClientInformationFull] = {}
        # broker-generated state (sent to Okta) -> the original Claude-side request
        self._pending: dict[str, tuple[OAuthClientInformationFull, AuthorizationParams, float]] = {}
        # broker-generated state -> the PKCE verifier for our own leg to Okta
        self._pkce_verifiers: dict[str, str] = {}
        # our own authorization code -> (AuthorizationCode, real Okta ID token)
        self._auth_codes: dict[str, tuple[AuthorizationCode, str]] = {}

    # -- Dynamic Client Registration: lets Claude self-register against THIS
    # gateway (unlike Okta, which doesn't support DCR for this app) --------

    async def get_client(self, client_id: str) -> OAuthClientInformationFull | None:
        return self._clients.get(client_id)

    async def register_client(self, client_info: OAuthClientInformationFull) -> None:
        self._clients[client_info.client_id] = client_info

    # -- Step 1->2: Claude's /authorize hits us; we redirect to Okta -------

    async def authorize(self, client: OAuthClientInformationFull, params: AuthorizationParams) -> str:
        if not settings.okta_issuer or not settings.okta_client_id or not settings.okta_client_secret:
            raise AuthorizeError(error="server_error", error_description="Okta broker is not configured")

        broker_state = secrets.token_urlsafe(32)
        self._pending[broker_state] = (client, params, time.time() + _PENDING_TTL_SECONDS)

        code_verifier = secrets.token_urlsafe(64)[:64]
        code_challenge = base64.urlsafe_b64encode(hashlib.sha256(code_verifier.encode()).digest()).decode().rstrip("=")
        # Needed again in handle_okta_callback below, once Okta's redirect comes back.
        self._pkce_verifiers[broker_state] = code_verifier

        okta_authorize_url = (
            f"{settings.okta_issuer}/v1/authorize?"
            + "&".join(
                f"{k}={v}"
                for k, v in {
                    "response_type": "code",
                    "client_id": settings.okta_client_id,
                    "redirect_uri": f"{settings.public_url}{OKTA_CALLBACK_PATH}",
                    # Deliberately narrow -- avoids the interclient_access/
                    # device_sso scopes that break Claude's own request.
                    "scope": "openid profile email",
                    "state": broker_state,
                    "code_challenge": code_challenge,
                    "code_challenge_method": "S256",
                }.items()
            )
        )
        return okta_authorize_url

    # -- Step 4->5: Okta's redirect lands here (not part of the SDK's own
    # routes -- this is the "another handler" the provider docstring says
    # implementations must add themselves) -------------------------------

    async def handle_okta_callback(self, request: Request) -> Response:
        broker_state = request.query_params.get("state")
        okta_code = request.query_params.get("code")
        pending = self._pending.pop(broker_state, None) if broker_state else None
        code_verifier = self._pkce_verifiers.pop(broker_state, None) if broker_state else None

        if not pending or not code_verifier or not okta_code:
            return Response("Invalid or expired login attempt. Please try connecting again.", status_code=400)

        client, params, expires_at = pending
        if time.time() > expires_at:
            return Response("Login attempt expired. Please try connecting again.", status_code=400)

        async with httpx.AsyncClient(timeout=10.0) as http_client:
            token_resp = await http_client.post(
                f"{settings.okta_issuer}/v1/token",
                data={
                    "grant_type": "authorization_code",
                    "code": okta_code,
                    "redirect_uri": f"{settings.public_url}{OKTA_CALLBACK_PATH}",
                    "code_verifier": code_verifier,
                    "client_id": settings.okta_client_id,
                    "client_secret": settings.okta_client_secret,
                },
            )
        if token_resp.status_code != 200:
            return Response(f"Okta token exchange failed: {token_resp.text}", status_code=502)

        okta_id_token = token_resp.json()["id_token"]

        our_code = secrets.token_urlsafe(32)
        self._auth_codes[our_code] = (
            AuthorizationCode(
                code=our_code,
                scopes=params.scopes or ["bigquery"],
                expires_at=time.time() + _AUTH_CODE_TTL_SECONDS,
                client_id=client.client_id,
                code_challenge=params.code_challenge,
                redirect_uri=params.redirect_uri,
                redirect_uri_provided_explicitly=params.redirect_uri_provided_explicitly,
            ),
            okta_id_token,
        )

        redirect_url = construct_redirect_uri(str(params.redirect_uri), code=our_code, state=params.state)
        return RedirectResponse(url=redirect_url, status_code=302)

    # -- Step 6: Claude redeems our code at /token (fully SDK-handled --
    # the SDK's TokenHandler already checked Claude's PKCE code_verifier
    # against the code_challenge stored on the AuthorizationCode below,
    # before ever calling this) -------------------------------------------

    async def load_authorization_code(
        self, client: OAuthClientInformationFull, authorization_code: str
    ) -> AuthorizationCode | None:
        entry = self._auth_codes.get(authorization_code)
        return entry[0] if entry else None

    async def exchange_authorization_code(
        self, client: OAuthClientInformationFull, authorization_code: AuthorizationCode
    ) -> OAuthToken:
        entry = self._auth_codes.pop(authorization_code.code, None)
        if entry is None:
            raise TokenError(error="invalid_grant", error_description="Authorization code already used or expired")
        _, okta_id_token = entry
        # No refresh_token issued -- a real, documented limitation for now.
        # Okta ID tokens are short-lived (~1hr); once one expires, Claude has
        # to redo the login rather than silently refresh. Fine for proving
        # the flow; worth revisiting before this is anything but a sandbox.
        return OAuthToken(access_token=okta_id_token, token_type="Bearer", expires_in=3600, scope="bigquery")

    # -- Verifying the token on every later tool call (this IS the real
    # Okta ID token from exchange_authorization_code above, unchanged) -----

    async def load_access_token(self, token: str) -> AccessToken | None:
        return verify_okta_id_token(token)

    # -- Not supported yet; see the refresh_token note above --------------

    async def load_refresh_token(self, client: OAuthClientInformationFull, refresh_token: str) -> RefreshToken | None:
        return None

    async def exchange_refresh_token(
        self, client: OAuthClientInformationFull, refresh_token: RefreshToken, scopes: list[str]
    ) -> OAuthToken:
        raise TokenError(error="unsupported_grant_type", error_description="Refresh is not supported yet")

    async def revoke_token(self, token: AccessToken | RefreshToken) -> None:
        pass
