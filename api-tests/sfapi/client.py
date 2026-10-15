"""A thin Salesforce REST client for the API test suite.

It deliberately returns raw ``requests.Response`` objects from ``request`` so
tests can assert on status codes, headers and error bodies, and offers a few
convenience helpers (create/get/update/delete/query) for test setup.
"""
from __future__ import annotations

import os
import time
from typing import Any, Iterable

import requests

DEFAULT_API_VERSION = "64.0"


class SalesforceApiError(AssertionError):
    """Raised by the convenience helpers when Salesforce returns an error."""

    def __init__(self, response: requests.Response):
        self.response = response
        try:
            detail = response.json()
        except ValueError:
            detail = response.text[:500]
        super().__init__(f"{response.request.method} {response.url} -> {response.status_code}: {detail}")


def soql_quote(value: str) -> str:
    """Quote a value for a SOQL string literal (escapes backslashes and quotes)."""
    escaped = value.replace("\\", "\\\\").replace("'", "\\'")
    return f"'{escaped}'"


class SalesforceClient:
    def __init__(self, instance_url: str, access_token: str, api_version: str = DEFAULT_API_VERSION,
                 timeout: float = 30.0):
        self.instance_url = instance_url.rstrip("/")
        self.api_version = api_version
        self.timeout = timeout
        self.session = requests.Session()
        self.session.headers.update({
            "Authorization": f"Bearer {access_token}",
            "Content-Type": "application/json",
            "Accept": "application/json",
        })

    # ------------------------------------------------------------------ setup

    @classmethod
    def from_env(cls, token_var: str = "SF_ACCESS_TOKEN") -> "SalesforceClient":
        url = os.environ.get("SF_INSTANCE_URL")
        token = os.environ.get(token_var)
        missing = [name for name, value in (("SF_INSTANCE_URL", url), (token_var, token)) if not value]
        if missing:
            raise RuntimeError(
                f"Missing environment variable(s): {', '.join(missing)}. "
                "Run `sf org display --json` against your org and export instanceUrl/accessToken, "
                "or see README.md > Running locally."
            )
        return cls(url, token, os.environ.get("SF_API_VERSION", DEFAULT_API_VERSION))

    @property
    def base_url(self) -> str:
        return f"{self.instance_url}/services/data/v{self.api_version}"

    # ------------------------------------------------------------------ raw access

    def request(self, method: str, path: str, **kwargs: Any) -> requests.Response:
        url = path if path.startswith("http") else f"{self.base_url}{path}"
        started = time.perf_counter()
        response = self.session.request(method, url, timeout=self.timeout, **kwargs)
        response.duration_s = time.perf_counter() - started  # type: ignore[attr-defined]
        return response

    # ------------------------------------------------------------------ helpers

    def create(self, sobject: str, fields: dict[str, Any]) -> str:
        r = self.request("POST", f"/sobjects/{sobject}", json=fields)
        if r.status_code != 201:
            raise SalesforceApiError(r)
        return r.json()["id"]

    def get(self, sobject: str, record_id: str, fields: Iterable[str] | None = None) -> dict[str, Any]:
        params = {"fields": ",".join(fields)} if fields else None
        r = self.request("GET", f"/sobjects/{sobject}/{record_id}", params=params)
        if r.status_code != 200:
            raise SalesforceApiError(r)
        return r.json()

    def update(self, sobject: str, record_id: str, fields: dict[str, Any]) -> None:
        r = self.request("PATCH", f"/sobjects/{sobject}/{record_id}", json=fields)
        if r.status_code != 204:
            raise SalesforceApiError(r)

    def delete(self, sobject: str, record_id: str) -> None:
        r = self.request("DELETE", f"/sobjects/{sobject}/{record_id}")
        if r.status_code not in (204, 404):
            raise SalesforceApiError(r)

    def query(self, soql: str) -> list[dict[str, Any]]:
        r = self.request("GET", "/query", params={"q": soql})
        if r.status_code != 200:
            raise SalesforceApiError(r)
        body = r.json()
        records = list(body["records"])
        while not body.get("done", True):
            r = self.request("GET", f"{self.instance_url}{body['nextRecordsUrl']}")
            if r.status_code != 200:
                raise SalesforceApiError(r)
            body = r.json()
            records.extend(body["records"])
        return records

    def describe(self, sobject: str) -> dict[str, Any]:
        r = self.request("GET", f"/sobjects/{sobject}/describe")
        if r.status_code != 200:
            raise SalesforceApiError(r)
        return r.json()
