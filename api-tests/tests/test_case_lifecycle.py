"""Happy-path case lifecycle over the REST API: create, read, escalate, close, delete."""
import pytest
from jsonschema import validate

from sfapi import soql_quote
from tests.schemas import CASE_RECORD, CREATE_RESPONSE

CASE_FIELDS = ["Id", "CaseNumber", "Subject", "Status", "Priority", "Origin", "IsClosed", "ClosedDate"]

pytestmark = pytest.mark.smoke


def test_create_case_returns_201_with_new_id(sf, created_ids, unique_subject):
    response = sf.request("POST", "/sobjects/Case", json={"Subject": unique_subject, "Origin": "Phone"})

    assert response.status_code == 201, response.text
    body = response.json()
    validate(body, CREATE_RESPONSE)
    created_ids.append(("Case", body["id"]))
    assert response.headers.get("Location", "").endswith(body["id"]), "Location header should point at the new record"


def test_created_case_matches_payload_and_contract(sf, make_case, unique_subject):
    case_id = make_case(Priority="High", Origin="Email")

    record = sf.get("Case", case_id, CASE_FIELDS)

    validate(record, CASE_RECORD)
    assert record["Subject"] == unique_subject
    assert record["Priority"] == "High"
    assert record["Origin"] == "Email"
    assert record["Status"] == "New"
    assert record["IsClosed"] is False


def test_escalate_case_with_patch(sf, make_case):
    case_id = make_case()

    response = sf.request("PATCH", f"/sobjects/Case/{case_id}", json={
        "Status": "Escalated",
        "Priority": "High",
        "Escalation_Reason__c": "Customer has had no power for 48 hours",
    })

    assert response.status_code == 204, response.text
    assert response.content == b"", "PATCH should return no body"
    record = sf.get("Case", case_id, ["Status", "Priority", "Escalation_Reason__c"])
    assert record["Status"] == "Escalated"
    assert record["Priority"] == "High"
    assert record["Escalation_Reason__c"] == "Customer has had no power for 48 hours"


def test_closing_a_case_sets_is_closed_and_closed_date(sf, make_case):
    case_id = make_case()

    sf.update("Case", case_id, {"Status": "Closed"})

    record = sf.get("Case", case_id, ["IsClosed", "ClosedDate", "Status"])
    assert record["Status"] == "Closed"
    assert record["IsClosed"] is True
    assert record["ClosedDate"], "ClosedDate should be stamped when the case closes"


def test_deleted_case_is_no_longer_retrievable(sf, unique_subject):
    case_id = sf.create("Case", {"Subject": unique_subject, "Origin": "Web"})

    delete = sf.request("DELETE", f"/sobjects/Case/{case_id}")
    get_after = sf.request("GET", f"/sobjects/Case/{case_id}")

    assert delete.status_code == 204
    assert get_after.status_code == 404
    assert get_after.json()[0]["errorCode"] in {"ENTITY_IS_DELETED", "NOT_FOUND"}


def test_soql_finds_case_by_subject(sf, make_case, unique_subject):
    case_id = make_case()

    rows = sf.query(f"SELECT Id, Subject FROM Case WHERE Subject = {soql_quote(unique_subject)}")

    assert [r["Id"] for r in rows] == [case_id]


def test_soql_quote_neutralises_injection(sf, make_case):
    make_case()
    hostile = "x' OR Subject LIKE '%"

    rows = sf.query(f"SELECT Id FROM Case WHERE Subject = {soql_quote(hostile)}")

    assert rows == [], "An escaped hostile value must match nothing rather than every case"


def test_composite_creates_case_and_comment_in_one_call(sf, created_ids, unique_subject):
    body = {
        "allOrNone": True,
        "compositeRequest": [
            {
                "method": "POST",
                "url": f"/services/data/v{sf.api_version}/sobjects/Case",
                "referenceId": "newCase",
                "body": {"Subject": unique_subject, "Origin": "Web"},
            },
            {
                "method": "POST",
                "url": f"/services/data/v{sf.api_version}/sobjects/CaseComment",
                "referenceId": "newComment",
                "body": {"ParentId": "@{newCase.id}", "CommentBody": "First response sent", "IsPublished": False},
            },
        ],
    }

    response = sf.request("POST", "/composite", json=body)

    assert response.status_code == 200, response.text
    results = {r["referenceId"]: r for r in response.json()["compositeResponse"]}
    assert results["newCase"]["httpStatusCode"] == 201
    assert results["newComment"]["httpStatusCode"] == 201
    case_id = results["newCase"]["body"]["id"]
    created_ids.append(("Case", case_id))
    comments = sf.query(f"SELECT CommentBody FROM CaseComment WHERE ParentId = '{case_id}'")
    assert [c["CommentBody"] for c in comments] == ["First response sent"]


def test_composite_all_or_none_rolls_back_on_failure(sf, unique_subject):
    body = {
        "allOrNone": True,
        "compositeRequest": [
            {
                "method": "POST",
                "url": f"/services/data/v{sf.api_version}/sobjects/Case",
                "referenceId": "goodCase",
                "body": {"Subject": unique_subject, "Origin": "Web"},
            },
            {
                "method": "POST",
                "url": f"/services/data/v{sf.api_version}/sobjects/Case",
                "referenceId": "badCase",
                "body": {"Subject": unique_subject, "Not_A_Real_Field__c": "boom"},
            },
        ],
    }

    response = sf.request("POST", "/composite", json=body)

    results = {r["referenceId"]: r for r in response.json()["compositeResponse"]}
    assert results["badCase"]["httpStatusCode"] == 400
    assert results["goodCase"]["httpStatusCode"] == 400, "The first insert should be rolled back"
    assert results["goodCase"]["body"][0]["errorCode"] == "PROCESSING_HALTED"
    assert sf.query(f"SELECT Id FROM Case WHERE Subject = {soql_quote(unique_subject)}") == []
