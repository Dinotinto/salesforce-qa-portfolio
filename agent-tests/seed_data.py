"""Looks up the records created by scripts/seed-agent-data.apex for this run."""
from __future__ import annotations

import os
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent.parent / "api-tests"))

from sfapi import SalesforceClient  # noqa: E402

# Must match the tag substituted into the seed script (CI uses the GitHub run id).
RUN_TAG = os.environ.get("AGENT_RUN_TAG", "local")
PREFIX = f"AGENT-SEED {RUN_TAG} "

SEED_SUBJECTS = {
    "STATUS_CASE": PREFIX + "Inverter offline",
    "ESCALATE_CASE": PREFIX + "Panels not producing",
    "CLOSED_CASE": PREFIX + "Billing question",
    "OTHER_CASE": PREFIX + "Other customer outage",
}

CASE_FIELDS = "Id, CaseNumber, Subject, Status, Priority, IsClosed, Escalation_Reason__c, CreatedDate, LastModifiedDate"


def _soql_string(value: str) -> str:
    return "'" + value.replace("\\", "\\\\").replace("'", "\\'") + "'"


def seeded_cases(sf: SalesforceClient) -> dict[str, dict]:
    subjects = ", ".join(_soql_string(s) for s in SEED_SUBJECTS.values())
    rows = sf.query(f"SELECT {CASE_FIELDS} FROM Case WHERE Subject IN ({subjects})")
    by_subject = {r["Subject"]: r for r in rows}
    missing = [s for s in SEED_SUBJECTS.values() if s not in by_subject]
    if missing:
        raise RuntimeError(f"Seed data missing {missing} for tag {RUN_TAG!r}. Run scripts/seed-agent-data.apex first.")
    return {key: by_subject[subject] for key, subject in SEED_SUBJECTS.items()}
