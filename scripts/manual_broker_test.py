#!/usr/bin/env python3
"""Full end-to-end test of AUTH_MODE=okta_broker, playing Claude's exact role:
register a client via Dynamic Client Registration, open a real browser for
the user to log into Okta, catch the gateway's own redirect back, redeem the
code at the gateway's /token, then make a genuine MCP client call with the
resulting token -- exercising every layer, same bar as
manual_mcp_okta_test.py, but through the broker flow (oauth_broker.py)
instead of Claude talking to Okta directly.

Prerequisites:
  - The gateway running locally in AUTH_MODE=okta_broker (a separate process):
      AUTH_MODE=okta_broker PUBLIC_URL=http://127.0.0.1:8080 \\
        OKTA_CLIENT_SECRET=<secret> python3 run.py
  - http://127.0.0.1:8080/oauth/okta/callback registered as a redirect URI
    on the Okta app (see Notes/GCP Sandbox/Commands Run - Sandbox Setup.md).

Usage:
    python3 scripts/manual_broker_test.py
"""

from __future__ import annotations

import asyncio
import http.server
import os
import secrets
import sys
import threading
import urllib.parse
import webbrowser
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))

import httpx2
from mcp import ClientSession
from mcp.client.streamable_http import streamable_http_client

# Defaults to local; set GATEWAY_URL to the deployed Cloud Run URL to test
# the real broker deployment instead of a locally-running instance.
GATEWAY_URL = os.environ.get("GATEWAY_URL", "http://127.0.0.1:8080")
REDIRECT_URI = "http://127.0.0.1:8090/callback"  # this script's own listener -- always local, since it's playing Claude's role, not the gateway's


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


def register_client() -> tuple[str, str]:
    resp = httpx2.post(
        f"{GATEWAY_URL}/register",
        json={"redirect_uris": [REDIRECT_URI], "client_name": "manual-broker-test"},
    )
    resp.raise_for_status()
    data = resp.json()
    print(f"Registered test client via DCR: {data['client_id']}")
    return data["client_id"], data["client_secret"]


def run_authorize_and_get_code(client_id: str, code_verifier: str, code_challenge: str) -> str:
    server = http.server.HTTPServer(("127.0.0.1", 8090), _CallbackHandler)
    threading.Thread(target=server.handle_request, daemon=True).start()

    authorize_url = f"{GATEWAY_URL}/authorize?" + urllib.parse.urlencode(
        {
            "response_type": "code",
            "client_id": client_id,
            "redirect_uri": REDIRECT_URI,
            "state": secrets.token_urlsafe(16),
            "code_challenge": code_challenge,
            "code_challenge_method": "S256",
        }
    )
    print(f"Opening browser to log in (via the gateway's own broker, not Okta directly):\n\n{authorize_url}\n")
    webbrowser.open(authorize_url)

    print("Waiting for login (up to 3 minutes)...")
    server.timeout = 180
    server.handle_request()

    code = _CallbackHandler.result.get("code")
    if not code:
        print("No authorization code received -- login timed out, was denied, or the redirect URI isn't registered in Okta.")
        sys.exit(1)
    print("Got our own authorization code back from the gateway.\n")
    return code


def redeem_code(client_id: str, client_secret: str, code: str, code_verifier: str) -> str:
    print("Exchanging our code for a token at the gateway's /token (oauth_broker.py's exchange_authorization_code)...")
    resp = httpx2.post(
        f"{GATEWAY_URL}/token",
        data={
            "grant_type": "authorization_code",
            "code": code,
            "redirect_uri": REDIRECT_URI,
            "client_id": client_id,
            "client_secret": client_secret,
            "code_verifier": code_verifier,
        },
    )
    resp.raise_for_status()
    access_token = resp.json()["access_token"]
    print("Got an access token -- this is the real Okta ID token, handed through unchanged.\n")
    return access_token


async def call_mcp_with_token(token: str) -> None:
    client = httpx2.AsyncClient(headers={"Authorization": f"Bearer {token}"}, timeout=30.0)
    url = f"{GATEWAY_URL}/mcp"
    print(f"Connecting to {url} as a real MCP client, with the broker-issued token attached...\n")

    async with streamable_http_client(url, http_client=client) as (read, write):
        async with ClientSession(read, write) as session:
            await session.initialize()
            print("MCP session established -- the gateway's own token was accepted.\n")

            print("=== list_datasets ===")
            print((await session.call_tool("list_datasets", {})).content)

            print("\n=== query ===")
            print((await session.call_tool("query", {"sql": "SELECT * FROM mcp_sandbox.test_rows ORDER BY id"})).content)


def main() -> None:
    import base64
    import hashlib

    code_verifier = secrets.token_urlsafe(64)[:64]
    code_challenge = base64.urlsafe_b64encode(hashlib.sha256(code_verifier.encode()).digest()).decode().rstrip("=")

    client_id, client_secret = register_client()
    code = run_authorize_and_get_code(client_id, code_verifier, code_challenge)
    token = redeem_code(client_id, client_secret, code, code_verifier)
    asyncio.run(call_mcp_with_token(token))


if __name__ == "__main__":
    main()
