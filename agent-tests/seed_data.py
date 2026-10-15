"""Looks up the records created by scripts/seed-agent-data.apex."""
from __future__ import annotations

import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent.parent / "api-tests"))

from sfapi import SalesforceClient  # noqa: E402

SEED_SUBJECTS = {
    "STATUS_CASE": "AGENT-SEED Inverter offline",
    "ESCALATE_CASE": "AGENT-SEED Panels not producing",
    "CLOSED_CASE": "AGENT-SEED Billing question",
    "OTHER_CASE": "AGENT-SEED Other customer outage",
}

CASE_FIELDS = "Id, CaseNumber, Subject, Status, Priority, IsClosed, Escalation_Reason__c, CreatedDate, LastModifiedDate"


def seeded_cases(sf: SalesforceClient) -> dict[str, dict]:
    rows = sf.query(f"SELECT {CASE_FIELDS} FROM Case WHERE Subject LIKE 'AGENT-SEED %'")
    by_subject = {r["Subject"]: r for r in rows}
    missing = [s for s in SEED_SUBJECTS.values() if s not in by_subject]
    if missing:
        raise RuntimeError(f"Seed data missing {missing}. Run: sf apex run --file scripts/seed-agent-data.apex")
    return {key: by_subject[subject] for key, subject in SEED_SUBJECTS.items()}
