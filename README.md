# MCP Gateway — Local Prototype

A working, runnable scaffold of the gateway described in `../Notes/MCP Connector - Implementation Plan.md` (Phase 1.4) and `../Notes/MCP Connector - Runtime Flow (Okta to BigQuery).md`. **This is a local testing sandbox, not the real deployment** — nothing here is wired into `gcp-foundation-artiva` or deployed anywhere. Its job is to let the MCP/BigQuery plumbing be built and tested *before* Artiva's real Okta/WIF credentials exist, and to be a concrete, inspectable answer to "what does the gateway actually look like."

It was built and smoke-tested against the real, currently-installed `mcp` Python SDK (v2.0.0) — every API used here (`MCPServer`, `TokenVerifier`, `get_access_token()`, `streamable_http_app()`) was verified against the installed package, not written from memory. A live end-to-end test (`ClientSession` → `initialize` → `list_tools` → `call_tool`) passed against a running instance of this server before this was handed off.

## Architecture note — a refinement found while building this

The earlier Runtime Flow doc described the gateway itself hosting `/authorize` and `/callback` and brokering the Okta redirect on Claude's behalf (a "the gateway IS the OAuth server" model). Building against the real SDK surfaced a cleaner, SDK-idiomatic alternative that this prototype uses instead: the gateway acts as a pure **MCP Resource Server** — it advertises Okta as the external Authorization Server (via `AuthSettings(issuer_url=...)`), and Claude completes the OAuth login **directly against Okta**, then sends the resulting Okta token straight through as the bearer token on every call. The gateway never runs `/authorize`/`/callback` itself; it only verifies whatever token Okta already issued.

This removes an entire layer of custom code (no session store, no redirect-brokering routes) and matches what the current MCP authorization spec is built around. **The one thing this doesn't verify:** whether Claude's custom-connector OAuth flow and Okta's app-integration settings are actually compatible end to end (e.g., whether Okta needs Dynamic Client Registration enabled, or a pre-registered static OAuth client for Claude) — that can only be confirmed once real Okta credentials exist. If it turns out Claude needs the older broker pattern instead, `auth_verifiers.py`/`server.py` are the two files that would change; the BigQuery and WIF-exchange logic (`federation.py`, `bigquery_tools.py`) stays the same either way.

Worth updating the Runtime Flow doc's Phase A to match once this is confirmed — flagging here rather than silently changing that doc.

## What's implemented vs. deferred

| | |
| :---- | :---- |
| **Implemented** | MCP server (`list_datasets`, `list_tables`, `query` tools), Okta token verification via JWKS, the WIF/STS token exchange (`federation.py`), a BigQuery client that runs as either the federated user or your own local `gcloud` identity, a `Dockerfile`, and Terraform (`terraform/`) that deploys this to Cloud Run in a personal sandbox project — live-tested end to end over the public internet |
| **Deferred / not built here** | **Token caching** — the WIF exchange currently re-runs on every single tool call rather than caching the ~1hr Google token, which the Runtime Flow doc flagged as an open decision, not yet made; production-grade session/credential storage; wiring any of this into `gcp-foundation-artiva` or Artiva's real GCP project |

## Deployed to Cloud Run (personal sandbox, not Artiva)

`terraform/` stands this up in a throwaway free-tier GCP project — see `../Notes/GCP Sandbox/Commands Run - Sandbox Setup.md` and `../History/STATUS.md` for how that project was set up. `terraform plan`/`apply` there creates: the Artifact Registry repo, a dedicated service account, and the Cloud Run service itself (bootstrapped against Google's public placeholder image so the service can exist before a real one is built, then repointed at the real image via `gcloud builds submit` + another `apply`).

**One non-obvious bug worth knowing if you redeploy this anywhere**: `mcp.streamable_http_app()` has its own `host` parameter (separate from whatever uvicorn binds to) that defaults to `"127.0.0.1"` and silently auto-scopes DNS-rebinding Host-header protection to just that address — any real deployment gets a cryptic "Invalid Host header" / HTTP 421 on every request. `server.py` now passes `transport_security` explicitly: disabled entirely for `AUTH_MODE=local` (that mode has no request-level auth of its own anyway — see `terraform/cloud_run.tf`'s `public_invoker` comment), and properly scoped to `PUBLIC_URL`'s hostname once `AUTH_MODE=okta` is in play.

**Also worth knowing**: Cloud Run pins to the exact image string you give it. Pushing a new image over the *same* tag does not trigger a new revision — Terraform only diffs the string, so it sees no change. Use a new tag (or a fully automated CI pipeline that always does) for every real deploy.

## Setup

```bash
cd artiva-mcp-gateway-prototype
python3 -m venv .venv && source .venv/bin/activate
pip install -r requirements.txt
cp .env.example .env
```

## Running it today, with zero Artiva inputs (`AUTH_MODE=local`, the default)

No auth is enforced; every BigQuery call uses your own local credentials instead of the Okta/WIF chain. This tests the MCP wiring and the actual BigQuery query path, independent of anything Artiva hasn't provided yet.

```bash
gcloud auth application-default login
# set BQ_PROJECT_ID in .env to a project you can query
python3 run.py
# serves http://127.0.0.1:8080/mcp
```

**Test it without Claude**, using the official MCP Inspector (Node-based devtool):

```bash
npx @modelcontextprotocol/inspector
# point it at http://127.0.0.1:8080/mcp (Streamable HTTP transport)
```

Or from Python directly:

```python
import asyncio
from mcp import ClientSession
from mcp.client.streamable_http import streamable_http_client

async def main():
    async with streamable_http_client("http://127.0.0.1:8080/mcp") as (read, write):
        async with ClientSession(read, write) as session:
            await session.initialize()
            print(await session.list_tools())
            print(await session.call_tool("query", {"sql": "SELECT 1 AS n"}))

asyncio.run(main())
```

## Running it in real mode (`AUTH_MODE=okta`)

Needs every value in `.env.example`'s Okta and WIF sections. Two ways to get them:

1. **Artiva's real tenant**, once the Implementation Plan's Phase 1 "Need from Artiva" inputs land (issuer URL, client ID, groups-claim name, WIF pool/provider IDs).
2. **Your own sandbox**, sooner — the design doc's own Appendix A evaluation used exactly this approach ("a separate Okta trial tenant and standalone GCP organization") to prove the architecture before touching Artiva's real environment. Same idea: a free Okta developer org + a WIF pool in a personal/test GCP project would let the full Okta → STS → BigQuery chain be exercised end to end before Phase 1 is unblocked.

## File map

```
src/
  config.py          settings, all env-driven
  auth_verifiers.py  OktaTokenVerifier -- verifies a bearer token against Okta's JWKS
  federation.py       the WIF/STS token exchange (Google's sts.googleapis.com/v1/token)
  bigquery_tools.py  BigQuery client + the three tool implementations
  server.py          wires it all into an MCPServer, exposes the ASGI app
run.py               uvicorn entrypoint
Dockerfile            builds the container Cloud Run runs
terraform/            Artifact Registry + Cloud Run + IAM for the sandbox deployment
```

## IDE note

If your editor flags the imports as unresolved, point it at `.venv/bin/python` as the interpreter — it's a local venv, not a global install.
