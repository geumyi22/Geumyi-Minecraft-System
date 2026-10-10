#!/usr/bin/env python3
"""Offline Day12 private-port ActiveStore candidate TRIAGE (never a WFP PASS).

Accepts only a sanitized operator-exported Day12-Firewall-Target JSON.
Filters explicit non-TCP protocols that older collectors counted as possible
matches and deduplicates by the single-capture ephemeral rule ordinal.
Does not infer effective WFP policy, listener owner, or admin rule identity.
"""
import argparse
import json
from collections import Counter
from pathlib import Path

PRIVATE = (25570, 25571, 25572, 25573, 25575, 25576, 25577, 25579)
TCP_OR_ANY = {"TCP", "6", "ANY", "*", "256"}
OPEN_FIELDS = (
    "program_scope", "local_address_scope", "remote_address_scope",
    "interface_scope", "service_scope",
)


def review(document):
    if not isinstance(document, dict) or document.get("schema") != 1 or (
        document.get("phase") != "12.10-firewall-target"
    ) or document.get("synthetic") is not False:
        raise ValueError("INVALID_REAL_DAY12_FIREWALL_TARGET_DOCUMENT")
    if document.get("result") != "CAPTURED_FOR_REVIEW" or (
        document.get("rule_filter_read_failures") != 0
    ) or document.get("error_categories"):
        raise ValueError("INCOMPLETE_FIREWALL_CAPTURE")
    backend = document.get("backend_tcp_port_review")
    if not isinstance(backend, list) or sorted(
        row.get("port") for row in backend if isinstance(row, dict)
    ) != sorted(PRIVATE):
        raise ValueError("EIGHT_PROTECTED_PORT_PROFILES_NOT_CAPTURED")
    rules = {}
    for port in backend:
        if port.get("result") != "CANDIDATE_REVIEW_ONLY":
            raise ValueError("A_PORT_ALREADY_CLAIMED_FINAL_PASS")
        for row in port.get("rules", []):
            if not isinstance(row, dict):
                raise ValueError("RULE_ROW_INVALID")
            index = row.get("ordinal")
            if type(index) is not int or index < 1:
                raise ValueError("UNTRUSTED_RULE_ORDINAL")
            if index in rules and rules[index] != row:
                raise ValueError("CONFLICTING_RULE_FIELDS_BY_ORDINAL")
            rules[index] = row
    if not rules:
        raise ValueError("EMPTY_CANDIDATE_INVENTORY_CANNOT_PROVE_SAFE")
    eligible = {
        ordinal: row for ordinal, row in rules.items()
        if str(row.get("protocol", "")).upper() in TCP_OR_ANY
    }
    if not eligible:
        raise ValueError("NO_TCP_CANDIDATE_EVIDENCE")
    allows = {i: r for i, r in eligible.items() if r.get("action") == "Allow"}
    blocks = {i: r for i, r in eligible.items() if r.get("action") == "Block"}
    incomplete = [i for i, r in eligible.items() if r.get("classification") != "CANDIDATE"]
    unrestricted = [
        i for i, r in allows.items()
        if all(r.get(k) == "ANY" for k in OPEN_FIELDS)
    ]
    broad = [
        i for i, r in allows.items()
        if r.get("program_scope") == "ANY" and
        r.get("remote_address_scope") == "ANY"
    ]
    return {
        "schema": 1,
        "phase": "12.10-firewall-offline-triage",
        "read_only": True, "synthetic": False,
        "input_created_at": document.get("generated_at", "UNSPECIFIED"),
        "captured_profiles": document.get("active_network_profiles", []),
        "captured_inbound_enabled_rules": document.get("enabled_inbound_rules_examined"),
        "canonical_backend_ports_private": "UNCHANGED_FAIL",
        "firewall_runtime_effective_pass": False,
        "release_allowed": False,
        "source_capture_has_all_private_ports": True,
        "source_candidates_all_protocols": len(rules),
        "tcp_or_any_protocol_candidates": len(eligible),
        "tcp_or_any_allow_candidates": len(allows),
        "tcp_or_any_block_candidates": len(blocks),
        "tcp_or_any_ambiguous_candidates": len(incomplete),
        "broad_allow_program_any_remote_any": len(broad),
        "fully_unrestricted_allow_candidates": len(unrestricted),
        # Snapshot-local ordinals are not Windows firewall rule IDs;
        # never use them for programmatic netsh/PowerShell deletion.
        "review_only_ordinal_numbers": sorted(unrestricted),
        "tcp_or_any_protocol_breakdown": dict(sorted(Counter(
            str(row.get("protocol", "UNKNOWN")) for row in eligible.values()
        ).items())),
        "notes": [
            "This is OFFLINE triage from a prior, time-scoped ActiveStore snapshot.",
            "An allow candidate is NOT proof of a reachable network path.",
            "A block candidate is NOT proof of effective Windows Filtering Platform precedence.",
            "Rule ordinals are snapshot-only and MUST NOT be passed to firewall mutation tools.",
            "Protocol 41 and ICMPv4/ICMPv6/IGMP are excluded from TCP candidate counts.",
            "Effective policy, OS socket ownership and other devices remain unproven.",
            "Protected Golden backups and running production servers are never modified.",
        ],
    }


def main():
    p = argparse.ArgumentParser()
    p.add_argument("input", type=Path)
    p.add_argument("--output", type=Path)
    args = p.parse_args()
    try:
        doc = json.loads(args.input.read_text(encoding="utf-8-sig"))
        summary = review(doc)
    except (OSError, ValueError, UnicodeError) as exc:
        print(json.dumps({"result": "REVIEW_BLOCKED", "error_type": type(exc).__name__}))
        return 2
    data = json.dumps(summary, ensure_ascii=False, indent=2) + "\n"
    if args.output:
        args.output.write_text(data, encoding="utf-8")
    else:
        print(data, end="")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
