"""Shared helper: complete a real Okta login via browser (PKCE, Authorization
Code flow), bypassing Claude entirely. Used by the manual test scripts --
see Notes/MCP Connector - Sandbox to Production Plan.md (Phase D) for why
this exists: Claude's own connector can't currently complete this login
against this Okta org (an unrelated scope-conflict issue), so this is how
the rest of the chain gets tested independent of that.
"""

from __future__ import annotations

import base64
import hashlib
import http.server
import os
import secrets
import sys
import threading
import urllib.parse
import webbrowser

import httpx

from src.config import settings

REDIRECT_URI = "http://localhost:8080/authorization-code/callback"


class _CallbackHandler(http.server.BaseHTTPRequestHandler):
    result: dict = {}

    def do_GET(self) -> None:
        params = urllib.parse.parse_qs(urllib.parse.urlparse(self.path).query)
        self.send_response(200)
        self.send_header("Content-type", "text/html")
        self.end_headers()
        if "code" in params:
            _CallbackHandler.result["code"] = params["code"][0]
            self.wfile.write(b"<html><body>Login captured -- you can close this tab.</body></html>")
        else:
            self.wfile.write(b"<html><body>No code received.</body></html>")

    def log_message(self, *args) -> None:  # quiet
        pass


def get_okta_id_token(scope: str = "openid profile email") -> str:
    """Opens a browser, waits for interactive login, returns a real Okta ID token.

    Requests only openid/profile/email -- deliberately avoiding the
    interclient_access/device_sso scopes that break Claude's own login
    against this org (see Notes/Claude-Okta Connector Issue - Summary &
    Path Forward.md).
    """
    client_secret = os.environ.get("OKTA_CLIENT_SECRET")
    if not client_secret:
        print("Set OKTA_CLIENT_SECRET in the environment first.")
        sys.exit(1)

    code_verifier = secrets.token_urlsafe(64)[:64]
    code_challenge = base64.urlsafe_b64encode(hashlib.sha256(code_verifier.encode()).digest()).decode().rstrip("=")

    _CallbackHandler.result = {}
    server = http.server.HTTPServer(("127.0.0.1", 8080), _CallbackHandler)
    threading.Thread(target=server.handle_request, daemon=True).start()

    auth_url = f"{settings.okta_issuer}/v1/authorize?" + urllib.parse.urlencode(
        {
            "response_type": "code",
            "client_id": settings.okta_client_id,
            "redirect_uri": REDIRECT_URI,
            "scope": scope,
            "state": secrets.token_urlsafe(16),
            "code_challenge": code_challenge,
            "code_challenge_method": "S256",
        }
    )
    print(f"Opening browser to log in:\n\n{auth_url}\n")
    webbrowser.open(auth_url)

    print("Waiting for login (up to 3 minutes)...")
    server.timeout = 180
    server.handle_request()  # blocks until the callback hits, or times out

    code = _CallbackHandler.result.get("code")
    if not code:
        print("No authorization code received -- login timed out or was denied.")
        sys.exit(1)

    print("Got authorization code. Exchanging for an Okta ID token...")
    token_resp = httpx.post(
        f"{settings.okta_issuer}/v1/token",
        data={
            "grant_type": "authorization_code",
            "code": code,
            "redirect_uri": REDIRECT_URI,
            "code_verifier": code_verifier,
            "client_id": settings.okta_client_id,
            "client_secret": client_secret,
        },
    )
    token_resp.raise_for_status()
    id_token = token_resp.json()["id_token"]
    print("Got Okta ID token.\n")
    return id_token
