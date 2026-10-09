#!/usr/bin/env python3
"""Fail-closed Day 12 Stable/Maintenance gate.

A missing section/key is never an implicit PASS. In particular, the native
IPv4/IPv6 backend Java/RCON listener bind + owner gate is mandatory even if
all other live activities were reported successful.
"""
import json
import sys
from pathlib import Path

REQUIRED_REPOSITORY_GATES = (
    "day12_read_only_safety_ci",
    "day12_security_sbom_ci",
    "gsc_reproducibility",
    "system_ci_after_final_source_cleanup",
    "synthetic_dr_ci",
)
REQUIRED_LIVE_GATES = (
    "phase_12_0A_baseline_capture",
    "phase_12_0B_protected_golden_checkpoint",
    "phase_12_1_managed_content_live_e2e",
    "phase_12_2_component_inventory",
    "phase_12_3_whole_system_health",
    "phase_12_4_lifecycle_dry_run_review",
    "phase_12_5_runtime_security_review",
    "phase_12_7_offline_known_good_startup",
    "phase_12_10_backend_ports_private",
    "phase_12_11_final_live_e2e",
    "phase_12_12_soak",
)

APPROVED_STATUS = "VERIFIED_ALL_MANDATORY_GATES"


def check_gates(document):
    failures = []
    if not isinstance(document, dict):
        return False, ["root=INVALID_TYPE"]
    if type(document.get("schema")) is not int or document["schema"] != 1:
        failures.append("schema=INVALID_OR_MISSING")
    if document.get("status") != APPROVED_STATUS:
        failures.append("status=NOT_FINAL_VERIFIED")

    for section, required in (
        ("repository_gates", REQUIRED_REPOSITORY_GATES),
        ("live_gates", REQUIRED_LIVE_GATES),
    ):
        values = document.get(section)
        if not isinstance(values, dict):
            failures.append(f"{section}=MISSING_OR_INVALID")
            continue
        for key in required:
            if key not in values:
                failures.append(f"{section}.{key}=MISSING")
        # Unknown gates may be added as the system evolves, but they must
        # pass too; extra keys cannot replace omitted mandatory entries.
        for key, value in values.items():
            if value != "PASS":
                failures.append(f"{section}.{key}=NOT_PASS")

    release = document.get("release")
    if not isinstance(release, dict):
        failures.append("release=MISSING_OR_INVALID")
    else:
        if release.get("stable_release_allowed") is not True:
            failures.append("release.stable_release_allowed=NOT_APPROVED")
        if release.get("maintenance_mode_allowed") is not True:
            failures.append("release.maintenance_mode_allowed=NOT_APPROVED")
    return not failures, failures


def main(argv=None):
    argv = sys.argv if argv is None else argv
    path = Path(argv[1] if len(argv) > 1 else "FINAL-RELEASE-GATES.json")
    try:
        document = json.loads(path.read_text(encoding="utf-8-sig"))
    except (OSError, UnicodeError, ValueError) as exc:
        print(json.dumps({
            "allowed": False,
            "blocking": ["GATES_JSON_UNREADABLE_OR_INVALID"],
            "error_type": type(exc).__name__,
        }, indent=2))
        return 2
    allowed, blocking = check_gates(document)
    print(json.dumps({"allowed": allowed, "blocking": blocking}, indent=2))
    return 0 if allowed else 2


if __name__ == "__main__":
    raise SystemExit(main())
