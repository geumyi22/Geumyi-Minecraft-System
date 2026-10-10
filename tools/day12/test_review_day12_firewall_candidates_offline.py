#!/usr/bin/env python3
"""Synthetic-only Day 12 firewall triage regression; no host network access."""
import copy
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path
import json

from review_day12_firewall_candidates_offline import PRIVATE, review


def fake_report():
    examples = [
        dict(ordinal=1, classification="CANDIDATE", action="Allow",
             protocol="Any", program_scope="ANY", local_address_scope="ANY",
             remote_address_scope="ANY", interface_scope="ANY", service_scope="ANY"),
        dict(ordinal=2, classification="POSSIBLE_UNKNOWN", action="Allow",
             protocol="ICMPv6", program_scope="ANY", remote_address_scope="ANY"),
        dict(ordinal=3, classification="CANDIDATE", action="Block",
             protocol="TCP", program_scope="SPECIFIC_REDACTED",
             local_address_scope="ANY", remote_address_scope="ANY",
             interface_scope="ANY", service_scope="ANY"),
        dict(ordinal=4, classification="CANDIDATE", action="Allow",
             protocol="TCP", program_scope="SPECIFIC_REDACTED",
             local_address_scope="ANY", remote_address_scope="ANY",
             interface_scope="ANY", service_scope="ANY"),
    ]
    return {
        "schema": 1,
        "phase": "12.10-firewall-target",
        "synthetic": False,  # Represents simulated *shape* of an operator capture.
        "read_only": True,
        "result": "CAPTURED_FOR_REVIEW",
        "generated_at": "2000-01-01T00:00:00Z",
        "enabled_inbound_rules_examined": 4,
        "rule_filter_read_failures": 0,
        "error_categories": [],
        "active_network_profiles": ["Private"],
        "backend_tcp_port_review": [
            {"port": p, "result": "CANDIDATE_REVIEW_ONLY", "rules": copy.deepcopy(examples)}
            for p in PRIVATE
        ],
    }


class OfflineFirewallCandidateTests(unittest.TestCase):
    def test_unique_ordinals_and_no_icmp_as_tcp(self):
        s = review(fake_report())
        self.assertEqual(s["source_candidates_all_protocols"], 4)
        self.assertEqual(s["tcp_or_any_protocol_candidates"], 3)
        self.assertEqual(s["tcp_or_any_allow_candidates"], 2)
        self.assertEqual(s["tcp_or_any_block_candidates"], 1)
        self.assertEqual(s["fully_unrestricted_allow_candidates"], 1)
        self.assertEqual(s["review_only_ordinal_numbers"], [1])
        self.assertEqual(s["canonical_backend_ports_private"], "UNCHANGED_FAIL")
        self.assertFalse(s["firewall_runtime_effective_pass"])
        self.assertFalse(s["release_allowed"])

    def test_missing_port_and_conflicting_rule_fail_closed(self):
        missing = fake_report()
        missing["backend_tcp_port_review"].pop()
        with self.assertRaises(ValueError):
            review(missing)
        inconsistent = fake_report()
        inconsistent["backend_tcp_port_review"][1]["rules"][0]["action"] = "Block"
        with self.assertRaises(ValueError):
            review(inconsistent)

    def test_capture_metadata_and_protocol_mismatch_fail_closed(self):
        for key, val in (
            ("result", "CHECK_REQUIRED"),
            ("synthetic", True),
            ("error_categories", ["FILTER_FAILED"]),
            ("rule_filter_read_failures", 3),
        ):
            with self.subTest(key=key):
                doc = fake_report()
                doc[key] = val
                with self.assertRaises(ValueError):
                    review(doc)
        all_icmp = fake_report()
        for port in all_icmp["backend_tcp_port_review"]:
            for row in port["rules"]:
                row["protocol"] = "ICMPv6"
        with self.assertRaises(ValueError):
            review(all_icmp)

    def test_cli_read_only_and_bad_json(self):
        src = Path(__file__).with_name("review_day12_firewall_candidates_offline.py")
        with tempfile.TemporaryDirectory(prefix="day12-fw-fixture-") as d:
            p = Path(d) / "prior.json"
            out = Path(d) / "triage.json"
            p.write_text(json.dumps(fake_report()), encoding="utf-8")
            ok = subprocess.run([sys.executable, str(src), str(p), "--output", str(out)],
                                capture_output=True, text=True, check=False)
            self.assertEqual(ok.returncode, 0, ok.stderr)
            x = json.loads(out.read_text(encoding="utf-8"))
            self.assertEqual(x["source_candidates_all_protocols"], 4)
            p.write_text("{broken", encoding="utf-8")
            bad = subprocess.run([sys.executable, str(src), str(p)],
                                 capture_output=True, text=True, check=False)
            self.assertEqual(bad.returncode, 2)


if __name__ == "__main__":
    unittest.main()
