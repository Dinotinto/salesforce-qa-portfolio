"""Error handling and API contract: every bad request gets a precise, well-formed error."""
import pytest
import requests
from jsonschema import validate

from sfapi import SalesforceClient
from tests.schemas import ERROR_RESPONSE

pytestmark = pytest.mark.negative


def assert_error(response: requests.Response, status: int, codes: set[str]) -> dict:
    assert response.status_code == status, f"expected {status}, got {response.status_code}: {response.text}"
    body = response.json()
    validate(body, ERROR_RESPONSE)
    assert body[0]["errorCode"] in codes, body
    return body[0]


def test_unknown_field_is_rejected(sf, unique_subject):
    response = sf.request("POST", "/sobjects/Case", json={"Subject": unique_subject, "Severity__c": "P1"})

    error = assert_error(response, 400, {"INVALID_FIELD"})
    assert "Severity__c" in error["message"]


def test_subject_longer_than_255_is_rejected(sf):
    response = sf.request("POST", "/sobjects/Case", json={"Subject": "x" * 256})

    error = assert_error(response, 400, {"STRING_TOO_LONG"})
    assert error.get("fields") == ["Subject"]


def test_malformed_json_is_rejected(sf):
    response = sf.request("POST", "/sobjects/Case", data='{"Subject": "unterminated')

    assert_error(response, 400, {"JSON_PARSER_ERROR"})


def test_bad_account_reference_is_rejected(sf, unique_subject):
    response = sf.request("POST", "/sobjects/Case", json={"Subject": unique_subject, "AccountId": "not-an-id"})

    assert_error(response, 400, {"MALFORMED_ID", "INVALID_CROSS_REFERENCE_KEY", "FIELD_INTEGRITY_EXCEPTION"})


def test_read_only_field_cannot_be_written(sf, make_case):
    case_id = make_case()

    response = sf.request("PATCH", f"/sobjects/Case/{case_id}", json={"CaseNumber": "99999999"})

    assert_error(response, 400, {"INVALID_FIELD_FOR_INSERT_UPDATE"})


def test_unknown_record_returns_404(sf):
    response = sf.request("GET", "/sobjects/Case/500000000000000AAA")

    assert_error(response, 404, {"NOT_FOUND"})


def test_malformed_soql_returns_400(sf):
    response = sf.request("GET", "/query", params={"q": "SELEC Id FROM Case"})

    assert_error(response, 400, {"MALFORMED_QUERY"})


def test_invalid_token_returns_401(sf):
    impostor = SalesforceClient(sf.instance_url, "00Dinvalid!token", sf.api_version)

    response = impostor.request("GET", "/sobjects/Case/describe")

    assert_error(response, 401, {"INVALID_SESSION_ID"})


def test_put_on_a_record_is_refused(sf, make_case):
    case_id = make_case()

    response = sf.request("PUT", f"/sobjects/Case/{case_id}", json={"Subject": "replace"})

    assert_error(response, 405, {"METHOD_NOT_ALLOWED"})
