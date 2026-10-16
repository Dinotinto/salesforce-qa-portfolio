"""Fill the Testing Center spec template with this run's seeded case numbers.

Usage:
    AGENT_RUN_TAG=local python agent-tests/render_spec.py --agent Case_Support_Agent

Verified test cases need a real MessagingSession for Ada (AGENT_ADA_SESSION_ID, or
--ada-session). Without one they are left out, and the snapshot records that, so
the side-effect checks know no verified escalation was attempted.
"""
from __future__ import annotations

import argparse
import json
import os
import re
from pathlib import Path

from seed_data import RUN_TAG, seeded_cases
from sfapi import SalesforceClient

HERE = Path(__file__).resolve().parent
CASE_START = re.compile(r"^  - utterance:", re.M)


def drop_cases_needing(text: str, placeholder: str) -> tuple[str, int]:
    """Remove every test case block that uses the given placeholder."""
    starts = [m.start() for m in CASE_START.finditer(text)]
    if not starts:
        return text, 0
    head, blocks = text[: starts[0]], [text[a:b] for a, b in zip(starts, starts[1:] + [len(text)])]
    kept = [b for b in blocks if "{{" + placeholder + "}}" not in b]
    return head + "".join(kept), len(blocks) - len(kept)


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--agent", required=True, help="API name of the agent under test")
    parser.add_argument("--ada-session", default=os.environ.get("AGENT_ADA_SESSION_ID", ""),
                        help="Id of a verified MessagingSession whose end user is linked to Ada's contact")
    parser.add_argument("--template", default=str(HERE / "specs" / "case-agent-tests.template.yaml"))
    parser.add_argument("--out", default=str(HERE / "specs" / "case-agent-tests.yaml"))
    parser.add_argument("--snapshot", default=str(HERE / "results" / "seed-before.json"),
                        help="Where to save the pre-run record state for the side-effect checks")
    args = parser.parse_args()

    sf = SalesforceClient.from_env()
    cases = seeded_cases(sf)

    values = {"AGENT_API_NAME": args.agent}
    for key, record in cases.items():
        values[key] = record["CaseNumber"]
        values[f"{key}_SHORT"] = str(int(record["CaseNumber"]))

    text = Path(args.template).read_text()
    verified = bool(args.ada_session.strip())
    dropped = 0
    if verified:
        values["ADA_SESSION_ID"] = args.ada_session.strip()
    else:
        text, dropped = drop_cases_needing(text, "ADA_SESSION_ID")
        print(f"::warning::AGENT_ADA_SESSION_ID not set: {dropped} verified test cases left out; "
              "running the unverified (spoofing) cases only.")

    rendered = re.sub(r"\{\{(\w+)\}\}", lambda m: values[m.group(1)], text)
    Path(args.out).write_text(rendered)

    Path(args.snapshot).parent.mkdir(parents=True, exist_ok=True)
    Path(args.snapshot).write_text(json.dumps(
        {"run_tag": RUN_TAG, "verified_cases_ran": verified, "cases": cases}, indent=2))
    print(f"wrote {args.out} for agent {args.agent} (tag {RUN_TAG}, verified={verified}): "
          + ", ".join(f"{k}={v}" for k, v in values.items() if k != "ADA_SESSION_ID"))


if __name__ == "__main__":
    main()
