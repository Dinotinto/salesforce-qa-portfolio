"""Security configuration checks.

The first group runs with the admin token and catches configuration drift: if
someone widens a permission set or opens up case sharing, these fail.

The @persona group logs in as a real Support_Viewer user (SF_VIEWER_ACCESS_TOKEN)
and proves the restrictions hold end to end over the API.
"""
import os

import pytest

from sfapi import soql_quote

pytestmark = pytest.mark.security


def object_perms(sf, permission_set: str, sobject: str) -> dict:
    rows = sf.query(
        "SELECT PermissionsRead, PermissionsCreate, PermissionsEdit, PermissionsDelete, "
        "PermissionsViewAllRecords, PermissionsModifyAllRecords FROM ObjectPermissions "
        f"WHERE Parent.Name = '{permission_set}' AND SobjectType = '{sobject}'"
    )
    return rows[0] if rows else {}


def field_perms(sf, permission_set: str, field: str) -> dict:
    rows = sf.query(
        "SELECT PermissionsRead, PermissionsEdit FROM FieldPermissions "
        f"WHERE Parent.Name = '{permission_set}' AND Field = '{field}'"
    )
    return rows[0] if rows else {"PermissionsRead": False, "PermissionsEdit": False}


# ---------------------------------------------------------------- configuration drift

def test_case_sharing_is_private(sf):
    rows = sf.query("SELECT InternalSharingModel, ExternalSharingModel FROM EntityDefinition WHERE QualifiedApiName = 'Case'")
    assert rows[0]["InternalSharingModel"] == "Private"
    assert rows[0]["ExternalSharingModel"] == "Private"


def test_support_agent_cannot_delete_or_see_all_cases(sf):
    perms = object_perms(sf, "Support_Agent", "Case")
    assert perms["PermissionsRead"] and perms["PermissionsCreate"] and perms["PermissionsEdit"]
    assert not perms["PermissionsDelete"], "Agents must not delete cases"
    assert not perms["PermissionsViewAllRecords"], "Agents must only see their own or shared cases"
    assert not perms["PermissionsModifyAllRecords"]


def test_support_viewer_is_read_only(sf):
    perms = object_perms(sf, "Support_Viewer", "Case")
    assert perms["PermissionsRead"]
    assert not any(perms[p] for p in ("PermissionsCreate", "PermissionsEdit", "PermissionsDelete",
                                      "PermissionsViewAllRecords", "PermissionsModifyAllRecords"))


@pytest.mark.parametrize("permission_set, readable, editable", [
    ("Support_Agent", True, True),
    ("Support_Viewer", False, False),
])
def test_internal_notes_field_level_security(sf, permission_set, readable, editable):
    perms = field_perms(sf, permission_set, "Case.Internal_Notes__c")
    assert perms["PermissionsRead"] is readable
    assert perms["PermissionsEdit"] is editable


def test_agent_running_user_gets_no_object_access(sf):
    """The customer-facing agent's permission set grants Apex actions only, never raw Case access."""
    assert object_perms(sf, "Case_Agent_Actions", "Case") == {}


# ---------------------------------------------------------------- persona: Support Viewer

@pytest.mark.persona
def test_viewer_cannot_see_internal_notes_in_describe(viewer_sf):
    fields = {f["name"] for f in viewer_sf.describe("Case")["fields"]}
    assert "Subject" in fields
    assert "Internal_Notes__c" not in fields


@pytest.mark.persona
def test_viewer_query_on_internal_notes_fails(viewer_sf):
    response = viewer_sf.request("GET", "/query", params={"q": "SELECT Id, Internal_Notes__c FROM Case LIMIT 1"})
    assert response.status_code == 400
    assert response.json()[0]["errorCode"] == "INVALID_FIELD"


@pytest.mark.persona
def test_viewer_cannot_create_cases(viewer_sf, unique_subject):
    response = viewer_sf.request("POST", "/sobjects/Case", json={"Subject": unique_subject})
    assert response.status_code in (400, 403)
    assert response.json()[0]["errorCode"].startswith(("INSUFFICIENT_ACCESS", "NOT_FOUND", "INVALID_TYPE"))


@pytest.mark.persona
def test_viewer_cannot_see_unshared_case(sf, viewer_sf, make_case):
    case_id = make_case()  # owned by the admin/integration user, not shared
    response = viewer_sf.request("GET", f"/sobjects/Case/{case_id}")
    assert response.status_code in (403, 404)


@pytest.mark.persona
def test_viewer_can_read_but_not_edit_shared_case(sf, viewer_sf, make_case, created_ids):
    username = os.environ.get("SF_VIEWER_USERNAME")
    if not username:
        pytest.skip("SF_VIEWER_USERNAME not set")
    viewer_id = sf.query(f"SELECT Id FROM User WHERE Username = {soql_quote(username)}")[0]["Id"]
    case_id = make_case()
    share_id = sf.create("CaseShare", {"CaseId": case_id, "UserOrGroupId": viewer_id, "CaseAccessLevel": "Read"})
    created_ids.append(("CaseShare", share_id))

    read = viewer_sf.request("GET", f"/sobjects/Case/{case_id}", params={"fields": "Subject,Status"})
    edit = viewer_sf.request("PATCH", f"/sobjects/Case/{case_id}", json={"Status": "Escalated"})

    assert read.status_code == 200
    assert edit.status_code in (400, 403)
    assert edit.json()[0]["errorCode"].startswith("INSUFFICIENT_ACCESS")
    assert sf.get("Case", case_id, ["Status"])["Status"] == "New"
