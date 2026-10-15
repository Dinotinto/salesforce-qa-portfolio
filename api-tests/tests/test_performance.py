"""Response-time budgets. Thresholds are deliberately generous for a Developer
Edition org; tighten them via env vars for a sandbox with real SLAs."""
import os
import statistics

import pytest

pytestmark = pytest.mark.performance

READ_P95_BUDGET_S = float(os.environ.get("READ_P95_BUDGET_S", "2.5"))
WRITE_P95_BUDGET_S = float(os.environ.get("WRITE_P95_BUDGET_S", "3.5"))
SAMPLES = int(os.environ.get("PERF_SAMPLES", "10"))


def p95(values: list[float]) -> float:
    return statistics.quantiles(values, n=20)[-1] if len(values) >= 2 else values[0]


def test_case_read_p95_within_budget(sf, make_case):
    case_id = make_case()
    durations = []
    for _ in range(SAMPLES):
        response = sf.request("GET", f"/sobjects/Case/{case_id}", params={"fields": "Id,Subject,Status"})
        assert response.status_code == 200
        durations.append(response.duration_s)

    assert p95(durations) <= READ_P95_BUDGET_S, f"read p95 {p95(durations):.2f}s over budget; samples={durations}"


def test_case_update_p95_within_budget(sf, make_case):
    case_id = make_case()
    durations = []
    for i in range(SAMPLES):
        response = sf.request("PATCH", f"/sobjects/Case/{case_id}", json={"Description": f"perf sample {i}"})
        assert response.status_code == 204
        durations.append(response.duration_s)

    assert p95(durations) <= WRITE_P95_BUDGET_S, f"write p95 {p95(durations):.2f}s over budget; samples={durations}"


def test_api_usage_headroom(sf):
    """Fail early if the org is close to its daily API limit, before it breaks other suites."""
    limits = sf.request("GET", "/limits").json()["DailyApiRequests"]
    used = limits["Max"] - limits["Remaining"]

    assert limits["Remaining"] > limits["Max"] * 0.10, f"only {limits['Remaining']} of {limits['Max']} API calls left ({used} used)"
