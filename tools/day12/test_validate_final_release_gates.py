#!/usr/bin/env python3
"""Offline, synthetic negative-path tests; never promote or modify a release."""
import copy
import json
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

from validate_final_release_gates import (
    APPROVED_STATUS,
    REQUIRED_LIVE_GATES,
    REQUIRED_REPOSITORY_GATES,
    check_gates,
)


def synthetic_all_pass():
    return {
        "schema": 1,
        "status": APPROVED_STATUS,
        "repository_gates": {key: "PASS" for key in REQUIRED_REPOSITORY_GATES},
        "live_gates": {key: "PASS" for key in REQUIRED_LIVE_GATES},
        "release": {
            "stable_release_allowed": True,
            "maintenance_mode_allowed": True,
        },
    }


class StableGateFailClosedTests(unittest.TestCase):
    def setUp(self):
        self.clean = synthetic_all_pass()

    def test_complete_fake_schema_is_only_positive_synthetic_fixture(self):
        self.assertTrue(check_gates(self.clean)[0])

    def test_actual_repo_manifest_stays_blocked_and_tracks_12_10(self):
        gates = Path(__file__).resolve().parents[2] / "FINAL-RELEASE-GATES.json"
        data = json.loads(gates.read_text(encoding="utf-8-sig"))
        self.assertIn("phase_12_10_backend_ports_private", data["live_gates"])
        allowed, _ = check_gates(data)
        if data.get("status") != APPROVED_STATUS or (
            data["live_gates"]["phase_12_10_backend_ports_private"] != "PASS"
        ):
            self.assertFalse(allowed)
        # This test must NOT block a future genuinely approved all-PASS
        # Stable manifest. Synthetic positive and negative fixtures below
        # exercise the validator independently from today's live state.

    def test_missing_sections_fail(self):
        for key in ("repository_gates", "live_gates", "release", "status", "schema"):
            with self.subTest(section=key):
                payload = copy.deepcopy(self.clean)
                payload.pop(key)
                self.assertFalse(check_gates(payload)[0])

    def test_missing_each_required_gate_fails_even_with_release_flags_true(self):
        for section in ("repository_gates", "live_gates"):
            for key in tuple(self.clean[section]):
                with self.subTest(section=section, gate=key):
                    payload = copy.deepcopy(self.clean)
                    del payload[section][key]
                    self.assertFalse(check_gates(payload)[0])

    def test_missing_backend_private_ports_never_passes(self):
        payload = copy.deepcopy(self.clean)
        payload["live_gates"].pop("phase_12_10_backend_ports_private")
        self.assertFalse(check_gates(payload)[0])
        payload["live_gates"]["phase_12_10_backend_ports_private"] = "FAIL_UNVERIFIED_NATIVE_OWNER_ADDRESS"
        self.assertFalse(check_gates(payload)[0])
        payload["live_gates"]["phase_12_10_backend_ports_private"] = "PASS"
        self.assertTrue(check_gates(payload)[0])

    def test_additional_unresolved_gate_blocks_release(self):
        payload = copy.deepcopy(self.clean)
        payload["live_gates"]["new_future_gate"] = "CHECK_REQUIRED"
        self.assertFalse(check_gates(payload)[0])

    def test_stable_status_and_flags_are_exact(self):
        for val in ("BLOCKED_UNTIL_ALL_MANDATORY_GATES_PASS", "READY", None):
            with self.subTest(status=val):
                payload = copy.deepcopy(self.clean)
                payload["status"] = val
                self.assertFalse(check_gates(payload)[0])
        for field in ("stable_release_allowed", "maintenance_mode_allowed"):
            for val in (False, "true", None, 1):
                with self.subTest(flag=field, value=val):
                    payload = copy.deepcopy(self.clean)
                    payload["release"][field] = val
                    self.assertFalse(check_gates(payload)[0])

    def test_invalid_types_and_schema_fail(self):
        for payload in ([], None, "PASS", {"schema": True}, {"schema": 2}):
            with self.subTest(payload=payload):
                self.assertFalse(check_gates(payload)[0])
        for section in ("repository_gates", "live_gates", "release"):
            for val in (None, [], "PASS"):
                with self.subTest(section=section, value=val):
                    payload = copy.deepcopy(self.clean)
                    payload[section] = val
                    self.assertFalse(check_gates(payload)[0])

    def test_cli_exit_codes_on_disposable_json_only(self):
        script = Path(__file__).with_name("validate_final_release_gates.py")
        with tempfile.TemporaryDirectory(prefix="day12-gate-synthetic-") as tmp:
            fixture = Path(tmp) / "gates.json"
            fixture.write_text(json.dumps(self.clean), encoding="utf-8")
            passed = subprocess.run([sys.executable, str(script), str(fixture)],
                                    capture_output=True, text=True, check=False)
            self.assertEqual(passed.returncode, 0)
            fixture.write_text(json.dumps({"schema": 1, "release": {
                "stable_release_allowed": True,
                "maintenance_mode_allowed": True
            }}), encoding="utf-8")
            blocked = subprocess.run([sys.executable, str(script), str(fixture)],
                                     capture_output=True, text=True, check=False)
            self.assertEqual(blocked.returncode, 2)
            self.assertFalse(json.loads(blocked.stdout)["allowed"])
            fixture.write_text("not-json", encoding="utf-8")
            broken = subprocess.run([sys.executable, str(script), str(fixture)],
                                    capture_output=True, text=True, check=False)
            self.assertEqual(broken.returncode, 2)


if __name__ == "__main__":
    unittest.main()
