#!/usr/bin/env python3
"""Full end-to-end test through the REAL MCP protocol, against the deployed
gateway, with a real Okta token attached as a Bearer header.

Unlike manual_okta_test.py (which calls federation.py/bigquery_tools.py
directly), this exercises every layer of the real request path:
  MCP transport -> OktaTokenVerifier (real token verification) ->
  server.py's claim extraction -> the WIF/STS exchange -> the BigQuery query
  -> the MCP response.

The only thing this doesn't test is Claude's own browser OAuth UX -- see
Notes/Claude-Okta Connector Issue - Summary & Path Forward.md for why that
piece is separately blocked (an Okta/Claude scope conflict, unrelated to
the gateway's own code).

Usage:
    OKTA_CLIENT_SECRET=<secret> python3 scripts/manual_mcp_okta_test.py
"""

from __future__ import annotations

import asyncio
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))

import httpx2
from mcp import ClientSession
from mcp.client.streamable_http import streamable_http_client

from scripts._okta_login import get_okta_id_token
from src.config import settings


async def _run(id_token: str) -> None:
    # Default httpx2 timeout is 5s -- too tight for a Cloud Run cold start
    # plus MCP's streaming response style.
    client = httpx2.AsyncClient(headers={"Authorization": f"Bearer {id_token}"}, timeout=30.0)
    url = f"{settings.public_url}/mcp"
    print(f"Connecting to {url} as a real MCP client, with the Okta token attached...\n")

    async with streamable_http_client(url, http_client=client) as (read, write):
        async with ClientSession(read, write) as session:
            await session.initialize()
            print("MCP session established -- OktaTokenVerifier accepted the token.\n")

            print("=== list_datasets ===")
            print((await session.call_tool("list_datasets", {})).content)

            print("\n=== list_tables ===")
            print((await session.call_tool("list_tables", {"dataset_id": "mcp_sandbox"})).content)

            print("\n=== query ===")
            print((await session.call_tool("query", {"sql": "SELECT * FROM mcp_sandbox.test_rows ORDER BY id"})).content)


def main() -> None:
    id_token = get_okta_id_token()
    asyncio.run(_run(id_token))


if __name__ == "__main__":
    main()
