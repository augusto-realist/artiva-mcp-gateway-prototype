#!/usr/bin/env python3
"""Get a real Okta token (bypassing Claude) and run the gateway's own
WIF/STS exchange + BigQuery query code directly, as plain function calls --
NOT through the MCP protocol. This tests src/federation.py and
src/bigquery_tools.py in isolation.

For a test that also goes through real MCP + the real OktaTokenVerifier
(everything except Claude's own browser login UX), see
manual_mcp_okta_test.py instead -- that one is the fuller validation.

Usage:
    OKTA_CLIENT_SECRET=<secret> python3 scripts/manual_okta_test.py
"""

from __future__ import annotations

import asyncio
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))

from scripts._okta_login import get_okta_id_token
from src import bigquery_tools, federation

TEST_SQL = "SELECT * FROM mcp_sandbox.test_rows ORDER BY id"


def main() -> None:
    id_token = get_okta_id_token()

    print("Exchanging it for a Google token via WIF/STS (src/federation.py)...")
    google_token = asyncio.run(federation.exchange_okta_token_for_google_token(id_token))
    print("Got Google access token.\n")

    print(f"Running as the federated user: {TEST_SQL}")
    rows = bigquery_tools.run_query(TEST_SQL, google_token)
    print("\nResult:")
    for row in rows:
        print(" ", row)


if __name__ == "__main__":
    main()
