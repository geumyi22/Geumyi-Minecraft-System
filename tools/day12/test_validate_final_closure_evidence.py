#!/usr/bin/env python3
"""Synthetic-only final closure health/security mismatch regression tests."""
import copy
import json
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

from validate_final_closure_evidence import (
    OWNER_SOURCES,
    review_closure_evidence,
)


def synthetic_health():
    return {
        "schema": 2, "synthetic": False, "fixture_mode": False, "read_only": True,
        "mutation_performed": False, "result": "PASS",
        "summary": {"pass": 19, "warn": 0, "fail": 0},
        "checks": [{"key": "backend_ports_private", "status": "PASS", "mandatory": True}],
        "native_provider_status": "CAPTURED",
        "native_providers": [{"source": s, "status": "CAPTURED"} for s in sorted(OWNER_SOURCES)],
        "listener_inventory_sources": ["GetExtendedTcpTable_OWNER_PID_IPv4"],
    }


def synthetic_security():
    return {
        "schema": 1, "phase": "12.5", "final_result": "PASS",
        "runtime_acl_firewall_api_review": "PASS", "critical_findings": [],
    }


class LiveClosureEvidenceFailClosedTests(unittest.TestCase):
    def setUp(self):
        self.health = synthetic_health()
        self.security = synthetic_security()

    def test_complete_coherent_fixture_only(self):
        self.assertTrue(review_closure_evidence(self.health, self.security)[0])

    def test_checked_in_production_evidence_still_blocks(self):
        root = Path(__file__).resolve().parents[2]
        health = json.loads((root / "FINAL-HEALTH-REPORT.json").read_text(encoding="utf-8-sig"))
        security = json.loads((root / "FINAL-SECURITY-REPORT.json").read_text(encoding="utf-8-sig"))
        if health.get("result") != "PASS" or security.get("final_result") != "PASS":
            self.assertFalse(review_closure_evidence(health, security)[0])

    def test_no_fake_native_owner_or_ipv6_coverage(self):
        for field, value in (
            ("native_provider_status", "PARTIAL"),
            ("native_providers", []),
            ("listener_inventory_sources", []),
            ("checks", []),
        ):
            with self.subTest(field=field):
                h = copy.deepcopy(self.health)
                h[field] = value
                self.assertFalse(review_closure_evidence(h, self.security)[0])
        for source in OWNER_SOURCES:
            with self.subTest(source=source):
                h = copy.deepcopy(self.health)
                h["native_providers"] = [
                    row for row in h["native_providers"] if row["source"] != source
                ]
                self.assertFalse(review_closure_evidence(h, self.security)[0])

    def test_bind_gate_fail_and_missing_or_duplicate(self):
        for value in ("FAIL", "PENDING_LIVE", "WARN", None):
            h = copy.deepcopy(self.health)
            h["checks"][0]["status"] = value
            self.assertFalse(review_closure_evidence(h, self.security)[0])
        h = copy.deepcopy(self.health)
        h["checks"][0]["mandatory"] = False
        self.assertFalse(review_closure_evidence(h, self.security)[0])
        h = copy.deepcopy(self.health)
        h["checks"].append(copy.deepcopy(h["checks"][0]))
        self.assertFalse(review_closure_evidence(h, self.security)[0])

    def test_not_live_or_not_immutable_readonly(self):
        for field, val in (
            ("synthetic", True), ("fixture_mode", True),
            ("read_only", False), ("mutation_performed", True),
            ("result", "FAIL"), ("summary", {"fail": 1}),
        ):
            with self.subTest(field=field):
                h = copy.deepcopy(self.health)
                h[field] = val
                self.assertFalse(review_closure_evidence(h, self.security)[0])

    def test_security_no_inferred_firewall_or_acl_approval(self):
        for field, val in (
            ("final_result", "PENDING_RUNTIME_REVIEW"),
            ("runtime_acl_firewall_api_review", "PENDING_LIVE"),
            ("critical_findings", [{"severity": "critical"}]),
            ("critical_findings", None),
        ):
            with self.subTest(field=field):
                s = copy.deepcopy(self.security)
                s[field] = val
                self.assertFalse(review_closure_evidence(self.health, s)[0])

    def test_invalid_shapes_and_missing_artifacts(self):
        self.assertFalse(review_closure_evidence(None, self.security)[0])
        self.assertFalse(review_closure_evidence(self.health, None)[0])
        with tempfile.TemporaryDirectory(prefix="day12-closure-synthetic-") as tmp:
            script = Path(__file__).with_name("validate_final_closure_evidence.py")
            root = Path(tmp)
            h = root / "FINAL-HEALTH-REPORT.json"
            s = root / "FINAL-SECURITY-REPORT.json"
            h.write_text(json.dumps(self.health), encoding="utf-8")
            s.write_text(json.dumps(self.security), encoding="utf-8")
            passed = subprocess.run([sys.executable, str(script), str(root)],
                                    capture_output=True, text=True, check=False)
            self.assertEqual(passed.returncode, 0)
            h.write_text(json.dumps({"result": "PASS", "schema": 2}), encoding="utf-8")
            blocked = subprocess.run([sys.executable, str(script), str(root)],
                                     capture_output=True, text=True, check=False)
            self.assertEqual(blocked.returncode, 2)
            self.assertFalse(json.loads(blocked.stdout)["allowed"])
            s.unlink()
            missing = subprocess.run([sys.executable, str(script), str(root)],
                                     capture_output=True, text=True, check=False)
            self.assertEqual(missing.returncode, 2)


if __name__ == "__main__":
    unittest.main()
