#!/usr/bin/env python3
"""Fail-closed source-only consistency check. Not a live release verifier."""
import json
import sys
from pathlib import Path

CLOSED_REQUIRED = {
    "12.0A", "12.0B", "12.3", "12.4", "12.7-cache", "12.8",
    "12.10-lan4", "12.10-lan6", "12.10-tail4", "12.10-tail6",
    "12.10-gsc-auth", "12.2-installed-provenance", "12.1-pack-assets",
}
OPEN_REQUIRED = {"12.1", "12.2", "12.4", "12.5", "12.7", "12.10", "12.11", "12.12", "12.13"}


def validate(ledger, gates):
    errors = []
    if not isinstance(ledger, dict) or ledger.get("schema") != 1:
        return ["LEDGER_SCHEMA_INVALID"]
    if not isinstance(gates, dict) or gates.get("schema") != 1:
        return ["GATES_SCHEMA_INVALID"]
    if ledger.get("release_allowed") is not False or ledger.get("maintenance_allowed") is not False:
        errors.append("LEDGER_RELEASE_MUST_REMAIN_BLOCKED")
    if gates.get("status") != "BLOCKED_UNTIL_ALL_MANDATORY_GATES_PASS":
        errors.append("MUST_NOT_AUTO_ACCEPT_FINAL_RELEASE_MANIFEST")
    release = gates.get("release") if isinstance(gates.get("release"), dict) else {}
    live_gates = gates.get("live_gates") if isinstance(gates.get("live_gates"), dict) else {}
    if release.get("stable_release_allowed") is not False:
        errors.append("FINAL_RELEASE_MANIFEST_NOT_BLOCKED")
    if ledger.get("canonical_backend_ports_private") != (
        live_gates.get("phase_12_10_backend_ports_private")
    ):
        errors.append("CANONICAL_SOCKET_OWNER_FAIL_MUST_MATCH")
    closed = ledger.get("closed_scoped_checks", [])
    opened = ledger.get("unresolved_release_requirements", [])
    if not isinstance(closed, list) or not isinstance(opened, list):
        return errors + ["NON_ARRAY_EVIDENCE_COLLECTION"]
    closed_codes = [r.get("code") for r in closed if isinstance(r, dict)]
    open_codes = [r.get("code") for r in opened if isinstance(r, dict)]
    if set(closed_codes) != CLOSED_REQUIRED or len(closed_codes) != len(CLOSED_REQUIRED):
        errors.append("CLOSED_SCOPED_EVIDENCE_KEYS_WRONG")
    if set(open_codes) != OPEN_REQUIRED or len(open_codes) != len(OPEN_REQUIRED):
        errors.append("OPEN_MANDATORY_WORKSTREAM_KEYS_WRONG")
    if not all(
        isinstance(r, dict) and isinstance(r.get("status"), str)
        and r["status"] not in ("PASS", "COMPLETE", "RELEASED")
        for r in opened
    ):
        errors.append("OPEN_WORKSTREAM_FALSE_COMPLETION")
    cache_rows = [r for r in closed if isinstance(r, dict) and r.get("code") == "12.7-cache"]
    if len(cache_rows) != 1 or cache_rows[0].get("status") != "REAL_HOST_PASS_IN_SCOPE" or (
        "84/84" not in cache_rows[0].get("scope", "")
    ):
        errors.append("REAL_CACHE_EVIDENCE_SCOPE_INVALID")
    offline_rows = [r for r in opened if isinstance(r, dict) and r.get("code") == "12.7"]
    if len(offline_rows) != 1 or "OPEN" not in offline_rows[0].get("status", ""):
        errors.append("OFFLINE_START_WAS_INCORRECTLY_CLOSED")
    for code in ("12.10-lan4", "12.10-lan6", "12.10-tail4", "12.10-tail6"):
        matching = [x for x in closed if isinstance(x, dict) and x.get("code") == code]
        if len(matching) != 1 or matching[0].get("status") != (
            "REAL_REMOTE_PATH_NEGATIVE_WITH_POSITIVE_CONTROL"
        ):
            errors.append("REMOTE_PATH_SCOPE_MISSING_" + code)
    if ledger.get("operator_private_reports_committed") is not False:
        errors.append("OPERATOR_PRIVATE_REPORT_COMMIT_DISALLOWED")
    return errors


def main(argv=None):
    args = sys.argv[1:] if argv is None else argv
    repo = Path(args[0]) if args else Path(".")
    try:
        ledger = json.loads((repo / "deploy/day12-scoped-evidence-ledger.json").read_text(encoding="utf-8"))
        gates = json.loads((repo / "FINAL-RELEASE-GATES.json").read_text(encoding="utf-8"))
        errors = validate(ledger, gates)
    except (OSError, ValueError, UnicodeError) as exc:
        errors = ["EVIDENCE_OR_GATES_READ_ERROR:" + type(exc).__name__]
    print(json.dumps({
        "result": "SCOPED_LEDGER_CONSISTENT_RELEASE_STILL_BLOCKED" if not errors else "REVIEW_BLOCKED",
        "blocking": errors,
        "real_host_new_tests_executed": False,
        "stable_release_allowed": False,
    }, indent=2))
    return 0 if not errors else 2


if __name__ == "__main__":
    raise SystemExit(main())
