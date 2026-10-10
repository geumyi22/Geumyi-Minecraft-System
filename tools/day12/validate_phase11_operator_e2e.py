#!/usr/bin/env python3
"""Review operator-collected 12.11 real-client E2E evidence, never a release gate.

Template is the authority for 25 required cases. CI can validate forms but
cannot conduct Java/Bedrock/GSCM device actions or approve live mutations.
"""
import json
import sys
from datetime import datetime
from pathlib import Path

VALID = {"NOT_RUN", "PASS", "FAIL", "BLOCKED", "NOT_APPLICABLE"}


def review(template, evidence):
    failures = []
    if not isinstance(template, dict) or template.get("schema") != 1:
        return {"result": "INVALID_TEMPLATE", "blocking": ["TEMPLATE_SCHEMA"]}
    cases = template.get("tests")
    if not isinstance(cases, list) or len(cases) != 25:
        return {"result": "INVALID_TEMPLATE", "blocking": ["TEMPLATE_CASE_COUNT"]}
    expected = {}
    for row in cases:
        if not isinstance(row, dict) or not isinstance(row.get("id"), str):
            return {"result": "INVALID_TEMPLATE", "blocking": ["TEMPLATE_CASE_INVALID"]}
        if row["id"] in expected:
            return {"result": "INVALID_TEMPLATE", "blocking": ["TEMPLATE_CASE_DUPLICATE"]}
        expected[row["id"]] = row
    if not isinstance(evidence, dict) or evidence.get("schema") != 1 or (
        evidence.get("phase") != "12.11"
    ):
        return {"result": "INVALID_OPERATOR_FORM", "blocking": ["OPERATOR_FORM_SCHEMA"]}
    if evidence.get("stable_allowed") is not False or (
        evidence.get("backend_ports_private") != "UNCHANGED_FAIL"
    ):
        return {"result": "INVALID_OPERATOR_FORM", "blocking": ["RELEASE_GATE_TAMPERING"]}
    rows = evidence.get("tests")
    if not isinstance(rows, list):
        return {"result": "INVALID_OPERATOR_FORM", "blocking": ["MISSING_TESTS"]}
    observed = {}
    for row in rows:
        if not isinstance(row, dict) or row.get("id") not in expected:
            failures.append("UNKNOWN_TEST_ID")
            continue
        key = row["id"]
        if key in observed:
            failures.append("DUPLICATE_TEST_ID")
        observed[key] = row
    if set(expected) != set(observed) or len(rows) != len(expected):
        failures.append("REQUIRED_CASES_NOT_COMPLETE")
    pass_count = fail_count = blocked_count = not_run_count = na_count = 0
    for test_id, req in expected.items():
        row = observed.get(test_id)
        if row is None:
            continue
        if row.get("section") != req["section"] or row.get("description") != req["description"] or (
            row.get("disruptive") is not req["disruptive"]
        ):
            failures.append("TEST_SCOPE_CHANGED")
        state = row.get("status")
        if state not in VALID:
            failures.append("UNRECOGNIZED_STATUS")
        elif state == "PASS":
            pass_count += 1
            if row.get("evidence_origin") != "REAL_OPERATOR":
                failures.append("PASS_WITHOUT_REAL_OPERATOR")
            if not isinstance(row.get("evidence_reference"), str) or (
                not row["evidence_reference"].strip()
            ):
                failures.append("PASS_WITHOUT_EVIDENCE_REFERENCE")
            try:
                ts = datetime.fromisoformat(str(row["observed_at"]).replace("Z", "+00:00"))
                if ts.tzinfo is None:
                    raise ValueError("offset missing")
            except (ValueError, KeyError, TypeError):
                failures.append("PASS_WITHOUT_OFFSET_TIME")
            if req["disruptive"] and row.get("operator_approved_disruptive_operation") is not True:
                failures.append("DISRUPTIVE_PASS_WITHOUT_EXPLICIT_APPROVAL")
        elif state == "FAIL":
            fail_count += 1
        elif state == "BLOCKED":
            blocked_count += 1
        elif state == "NOT_APPLICABLE":
            na_count += 1
            # GSCM iOS, backups, restoring and control flows should not be
            # silently removed from the final live E2E gate.
            failures.append("MANDATORY_CASE_NOT_APPLICABLE")
        elif state == "NOT_RUN":
            not_run_count += 1
    status = (
        "EVIDENCE_INVALID" if failures else
        "OBSERVED_FAILURES" if fail_count else
        "INCOMPLETE_E2E" if (blocked_count or not_run_count or na_count) else
        "OPERATOR_REPORTED_ALL_TESTS_REQUIRE_INDEPENDENT_REVIEW"
    )
    return {
        "phase": "12.11",
        "result": status,
        "schema": 1,
        "case_count": len(expected),
        "pass_count": pass_count,
        "fail_count": fail_count,
        "blocked_count": blocked_count,
        "not_run_count": not_run_count,
        "not_applicable_count": na_count,
        "blocking": sorted(set(failures)),
        "operator_reported_complete": bool(
            status == "OPERATOR_REPORTED_ALL_TESTS_REQUIRE_INDEPENDENT_REVIEW"
        ),
        "independent_live_acceptance_proven": False,
        "stable_allowed": False,
        "backend_ports_private": "UNCHANGED_FAIL",
        "note": (
            "Form review validates recorded human claims and scopes only. "
            "It never executes game clients, operations, updates or Host reboot."
        ),
    }


def main(argv=None):
    import argparse
    parser = argparse.ArgumentParser()
    parser.add_argument("form", type=Path)
    parser.add_argument("--template", type=Path,
                        default=Path("deploy/day12-final-live-e2e-checklist.json"))
    args = parser.parse_args(argv)
    try:
        template = json.loads(args.template.read_text(encoding="utf-8-sig"))
        evidence = json.loads(args.form.read_text(encoding="utf-8-sig"))
        result = review(template, evidence)
    except (OSError, ValueError, UnicodeError):
        result = {"result": "INVALID_OR_MISSING_JSON", "stable_allowed": False}
    print(json.dumps(result, ensure_ascii=False, indent=2))
    return 0 if result.get("result") in (
        "INCOMPLETE_E2E", "OPERATOR_REPORTED_ALL_TESTS_REQUIRE_INDEPENDENT_REVIEW",
    ) else 2


if __name__ == "__main__":
    raise SystemExit(main())
