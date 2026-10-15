"""Fill the Testing Center spec template with the seeded case numbers.

Usage:
    python agent-tests/render_spec.py --agent Case_Support_Agent \
        --out agent-tests/specs/case-agent-tests.yaml
"""
from __future__ import annotations

import argparse
import json
import re
from pathlib import Path

from seed_data import seeded_cases
from sfapi import SalesforceClient

HERE = Path(__file__).resolve().parent


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--agent", required=True, help="API name of the agent under test")
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
    rendered = re.sub(r"\{\{(\w+)\}\}", lambda m: values[m.group(1)], text)
    Path(args.out).write_text(rendered)

    Path(args.snapshot).parent.mkdir(parents=True, exist_ok=True)
    Path(args.snapshot).write_text(json.dumps(cases, indent=2))
    print(f"wrote {args.out} for agent {args.agent}: " + ", ".join(f"{k}={v}" for k, v in values.items()))


if __name__ == "__main__":
    main()
