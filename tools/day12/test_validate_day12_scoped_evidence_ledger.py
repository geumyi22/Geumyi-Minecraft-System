#!/usr/bin/env python3
"""Synthetic negative cases for bounded Day12 progress ledger."""
import copy
import json
import unittest
from pathlib import Path
from validate_day12_scoped_evidence_ledger import validate

ROOT=Path(__file__).resolve().parents[2]
LEDGER=json.loads((ROOT/"deploy/day12-scoped-evidence-ledger.json").read_text(encoding="utf-8"))
GATES=json.loads((ROOT/"FINAL-RELEASE-GATES.json").read_text(encoding="utf-8"))

class LedgerTests(unittest.TestCase):
    def test_real_scoped_evidence_can_be_recorded_with_release_blocked(self):
        self.assertEqual(validate(LEDGER,GATES),[])

    def test_fail_if_socket_owner_falsely_promoted(self):
        d=copy.deepcopy(LEDGER)
        d["canonical_backend_ports_private"]="PASS"
        self.assertIn("CANONICAL_SOCKET_OWNER_FAIL_MUST_MATCH",validate(d,GATES))

    def test_fail_if_offline_start_is_promoted_from_cache_hash(self):
        d=copy.deepcopy(LEDGER)
        next(x for x in d["unresolved_release_requirements"] if x["code"]=="12.7")["status"]="PASS"
        errors=validate(d,GATES)
        self.assertIn("OPEN_WORKSTREAM_FALSE_COMPLETION",errors)
        self.assertIn("OFFLINE_START_WAS_INCORRECTLY_CLOSED",errors)

    def test_fail_if_e2e_soak_or_native_owner_open_workstream_deleted(self):
        for key in ("12.10","12.11","12.12"):
            with self.subTest(key=key):
                d=copy.deepcopy(LEDGER)
                d["unresolved_release_requirements"]=[
                    x for x in d["unresolved_release_requirements"] if x["code"]!=key
                ]
                self.assertIn("OPEN_MANDATORY_WORKSTREAM_KEYS_WRONG",validate(d,GATES))

    def test_final_gate_approval_in_source_without_evidence_refused(self):
        g=copy.deepcopy(GATES)
        g["status"]="VERIFIED_ALL_MANDATORY_GATES"
        g["release"]["stable_release_allowed"]=True
        errors=validate(LEDGER,g)
        self.assertIn("MUST_NOT_AUTO_ACCEPT_FINAL_RELEASE_MANIFEST",errors)
        self.assertIn("FINAL_RELEASE_MANIFEST_NOT_BLOCKED",errors)

    def test_corrupt_gate_sections_fail_closed(self):
        for section in ("release", "live_gates"):
            with self.subTest(section=section):
                g = copy.deepcopy(GATES)
                g[section] = None
                self.assertNotEqual(validate(LEDGER, g), [])

    def test_missing_fourth_real_network_path_not_valid(self):
        d=copy.deepcopy(LEDGER)
        d["closed_scoped_checks"]=[
          x for x in d["closed_scoped_checks"] if x["code"]!="12.10-tail6"
        ]
        self.assertIn("CLOSED_SCOPED_EVIDENCE_KEYS_WRONG",validate(d,GATES))

if __name__=="__main__":
    unittest.main()
