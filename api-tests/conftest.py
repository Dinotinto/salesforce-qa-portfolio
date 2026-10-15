"""Shared fixtures for the REST API suite.

Environment (CI sets these from `sf org display --json`):
    SF_INSTANCE_URL         e.g. https://yourdomain.my.salesforce.com
    SF_ACCESS_TOKEN         admin/integration user's access token
    SF_API_VERSION          optional, defaults to 64.0
    SF_VIEWER_ACCESS_TOKEN  optional, token for a user with only Support_Viewer
                            (enables the @persona tests)
"""
from __future__ import annotations

import os
import uuid
from typing import Callable, Iterator

import pytest

from sfapi import SalesforceClient, soql_quote

RUN_ID = uuid.uuid4().hex[:8]
SUBJECT_PREFIX = f"QA-API-{RUN_ID}"


@pytest.fixture(scope="session")
def sf() -> SalesforceClient:
    return SalesforceClient.from_env()


@pytest.fixture(scope="session")
def viewer_sf() -> SalesforceClient:
    if not os.environ.get("SF_VIEWER_ACCESS_TOKEN"):
        pytest.skip("SF_VIEWER_ACCESS_TOKEN not set; persona tests need a Support_Viewer user's token")
    return SalesforceClient.from_env("SF_VIEWER_ACCESS_TOKEN")


@pytest.fixture(scope="session")
def created_ids(sf: SalesforceClient) -> Iterator[list[tuple[str, str]]]:
    """Records created during the run, deleted at the end (children first)."""
    ids: list[tuple[str, str]] = []
    yield ids
    for sobject, record_id in reversed(ids):
        try:
            sf.delete(sobject, record_id)
        except AssertionError as exc:  # keep cleaning up; report at the end
            print(f"cleanup failed for {sobject} {record_id}: {exc}")
    # Belt and braces: anything this run created but failed to register.
    for row in sf.query(f"SELECT Id FROM Case WHERE Subject LIKE {soql_quote(SUBJECT_PREFIX + '%')}"):
        sf.delete("Case", row["Id"])


@pytest.fixture
def unique_subject(request: pytest.FixtureRequest) -> str:
    return f"{SUBJECT_PREFIX} {request.node.name}"[:255]


@pytest.fixture
def make_case(sf: SalesforceClient, created_ids: list, unique_subject: str) -> Callable[..., str]:
    def _make(**overrides) -> str:
        fields = {
            "Subject": unique_subject,
            "Description": "Created by the API regression suite",
            "Status": "New",
            "Origin": "Web",
            "Priority": "Medium",
        }
        fields.update(overrides)
        record_id = sf.create("Case", fields)
        created_ids.append(("Case", record_id))
        return record_id

    return _make
