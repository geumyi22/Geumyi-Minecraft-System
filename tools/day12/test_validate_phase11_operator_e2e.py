#!/usr/bin/env python3
"""Synthetic-only 12.11 operator evidence form regressions, no live operations."""
import copy
import json
import unittest
from pathlib import Path
from validate_phase11_operator_e2e import review

ROOT = Path(__file__).resolve().parents[2]
TEMPLATE = json.loads((ROOT / "deploy/day12-final-live-e2e-checklist.json").read_text(encoding="utf-8"))


class E2EFormTests(unittest.TestCase):
    def test_all_pending_remains_pending(self):
        d = review(TEMPLATE, TEMPLATE)
        self.assertEqual(d["case_count"], 25)
        self.assertEqual(d["not_run_count"], 25)
        self.assertEqual(d["result"], "INCOMPLETE_E2E")
        self.assertFalse(d["stable_allowed"])

    def test_fake_pass_is_refused(self):
        x = copy.deepcopy(TEMPLATE)
        x["tests"][0]["status"] = "PASS"
        d = review(TEMPLATE, x)
        self.assertEqual(d["result"], "EVIDENCE_INVALID")
        self.assertIn("PASS_WITHOUT_REAL_OPERATOR", d["blocking"])
        self.assertIn("PASS_WITHOUT_EVIDENCE_REFERENCE", d["blocking"])
        self.assertIn("DISRUPTIVE_PASS_WITHOUT_EXPLICIT_APPROVAL", d["blocking"])

    def test_claimed_real_pass_requires_independent_review(self):
        x = copy.deepcopy(TEMPLATE)
        for test in x["tests"]:
            test.update(status="PASS", evidence_origin="REAL_OPERATOR",
                        observed_at="2026-10-10T10:22:00+09:00",
                        evidence_reference="private-operator-evidence-id",
                        operator_approved_disruptive_operation=True)
        d = review(TEMPLATE, x)
        self.assertEqual(d["result"], "OPERATOR_REPORTED_ALL_TESTS_REQUIRE_INDEPENDENT_REVIEW")
        self.assertFalse(d["independent_live_acceptance_proven"])
        self.assertFalse(d["stable_allowed"])

    def test_removed_or_added_tests_are_invalid(self):
        x = copy.deepcopy(TEMPLATE)
        x["tests"].pop()
        self.assertEqual(review(TEMPLATE, x)["result"], "EVIDENCE_INVALID")
        x = copy.deepcopy(TEMPLATE)
        x["tests"].append(copy.deepcopy(x["tests"][0]))
        self.assertEqual(review(TEMPLATE, x)["result"], "EVIDENCE_INVALID")

    def test_missing_release_guard_blocks(self):
        x = copy.deepcopy(TEMPLATE)
        x["stable_allowed"] = True
        self.assertEqual(review(TEMPLATE, x)["result"], "INVALID_OPERATOR_FORM")

    def test_na_cannot_bypass_ios_or_backup(self):
        x = copy.deepcopy(TEMPLATE)
        i = next(r for r in x["tests"] if r["id"] == "GSCM_IOS_STATUS_AND_CONTROL")
        i["status"] = "NOT_APPLICABLE"
        d = review(TEMPLATE, x)
        self.assertEqual(d["result"], "EVIDENCE_INVALID")
        self.assertIn("MANDATORY_CASE_NOT_APPLICABLE", d["blocking"])


if __name__ == "__main__":
    unittest.main()
