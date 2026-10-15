"""JSON schemas for contract checks on Salesforce REST responses."""

CREATE_RESPONSE = {
    "type": "object",
    "required": ["id", "success", "errors"],
    "properties": {
        "id": {"type": "string", "pattern": "^500[A-Za-z0-9]{12}([A-Za-z0-9]{3})?$"},
        "success": {"const": True},
        "errors": {"type": "array", "maxItems": 0},
    },
}

ERROR_RESPONSE = {
    "type": "array",
    "minItems": 1,
    "items": {
        "type": "object",
        "required": ["errorCode", "message"],
        "properties": {
            "errorCode": {"type": "string", "minLength": 1},
            "message": {"type": "string", "minLength": 1},
            "fields": {"type": "array", "items": {"type": "string"}},
        },
    },
}

CASE_RECORD = {
    "type": "object",
    "required": ["attributes", "Id", "CaseNumber", "Subject", "Status", "Priority", "Origin", "IsClosed"],
    "properties": {
        "attributes": {
            "type": "object",
            "required": ["type", "url"],
            "properties": {"type": {"const": "Case"}},
        },
        "Id": {"type": "string", "pattern": "^500"},
        "CaseNumber": {"type": "string", "pattern": "^[0-9]{8}$"},
        "Subject": {"type": "string"},
        "Status": {"type": "string"},
        "Priority": {"type": "string", "enum": ["High", "Medium", "Low"]},
        "Origin": {"type": ["string", "null"]},
        "IsClosed": {"type": "boolean"},
        "ClosedDate": {"type": ["string", "null"]},
    },
}
