#!/usr/bin/env python3
"""Day 12 live-health closure integrity guard (offline, read-only).

The final release JSON gate cannot be used to bypass a conflicting real
FINAL-HEALTH-REPORT.json or FINAL-SECURITY-REPORT.json. Missing evidence is
always a release BLOCK, even if declarative approval flags say true.
"""
import json
import sys
from pathlib import Path

OWNER_SOURCES = {
    "GetExtendedTcpTable_OWNER_PID_IPv4",
    "GetExtendedTcpTable_OWNER_PID_IPv6",
}

# For Stable closure, ALL four internal Java/RCON pairs must be running and
# independently observed. A subset of online servers is insufficient.
PRIVATE_PORTS = frozenset((25570, 25571, 25572, 25573, 25575, 25576, 25577, 25579))
LOOPBACK_ADDRESSES = frozenset(("127.0.0.1", "::1", "::ffff:127.0.0.1"))


def review_closure_evidence(health, security):
    reasons = []
    if not isinstance(health, dict) or health.get("schema") != 2:
        reasons.append("FINAL_HEALTH_SCHEMA_INVALID")
    else:
        if health.get("synthetic") is not False or health.get("fixture_mode") is not False:
            reasons.append("FINAL_HEALTH_NOT_LIVE")
        if health.get("read_only") is not True or health.get("mutation_performed") is not False:
            reasons.append("FINAL_HEALTH_CAPTURE_CONTRACT_INVALID")
        if health.get("result") != "PASS":
            reasons.append("FINAL_HEALTH_NOT_PASS")
        summary = health.get("summary")
        if not isinstance(summary, dict) or type(summary.get("fail")) is not int or summary["fail"] != 0:
            reasons.append("FINAL_HEALTH_MANDATORY_FAILURE")
        checks = health.get("checks")
        if not isinstance(checks, list):
            reasons.append("FINAL_HEALTH_CHECKS_MISSING")
        else:
            matching = [row for row in checks if isinstance(row, dict) and
                        row.get("key") == "backend_ports_private"]
            if len(matching) != 1 or matching[0].get("status") != "PASS" or (
                matching[0].get("mandatory") is not True
            ):
                reasons.append("BACKEND_NATIVE_PRIVATE_PORT_GATE_NOT_PASS")
        if health.get("native_provider_status") != "CAPTURED":
            reasons.append("NATIVE_IPV4_IPV6_STATUS_NOT_CAPTURED")
        providers = health.get("native_providers")
        if not isinstance(providers, list) or not OWNER_SOURCES.issubset({
            row.get("source") for row in providers
            if isinstance(row, dict) and row.get("status") == "CAPTURED"
        }):
            reasons.append("NATIVE_IPV4_IPV6_OWNER_SOURCES_INCOMPLETE")
        sources = health.get("listener_inventory_sources")
        if not isinstance(sources, list) or not OWNER_SOURCES.intersection(
            item for item in sources if isinstance(item, str)
        ):
            reasons.append("NO_NATIVE_OWNER_LISTENER_ROWS")

        # Recheck the redacted per-port ledger, not merely its self-reported
        # PASS flag. The live verifier owns PID/process checks in-memory; this
        # independent closure check insists all eight protected listeners were
        # actually captured with an OWNER_PID provider and loopback address.
        listeners = health.get("listener_inventory")
        if not isinstance(listeners, list):
            reasons.append("PRIVATE_LISTENER_INVENTORY_MISSING")
        else:
            native_verified_ports = set()
            for row in listeners:
                if not isinstance(row, dict):
                    reasons.append("PRIVATE_LISTENER_ROW_INVALID")
                    continue
                port = row.get("port")
                if type(port) is not int or port not in PRIVATE_PORTS:
                    continue
                if row.get("address_scope") != "LOOPBACK" or (
                    row.get("address") not in LOOPBACK_ADDRESSES
                ):
                    reasons.append("PRIVATE_LISTENER_NON_LOOPBACK_OR_UNVERIFIED")
                if row.get("source") in OWNER_SOURCES and (
                    row.get("address_scope") == "LOOPBACK"
                    and row.get("address") in LOOPBACK_ADDRESSES
                ):
                    native_verified_ports.add(port)
            if native_verified_ports != PRIVATE_PORTS:
                reasons.append("PRIVATE_LISTENER_NATIVE_EIGHT_PORTS_INCOMPLETE")

    if not isinstance(security, dict) or security.get("schema") != 1:
        reasons.append("FINAL_SECURITY_SCHEMA_INVALID")
    else:
        if security.get("phase") != "12.5" or security.get("final_result") != "PASS":
            reasons.append("FINAL_SECURITY_REVIEW_NOT_PASS")
        if security.get("runtime_acl_firewall_api_review") != "PASS":
            reasons.append("FIREWALL_ACL_RUNTIME_REVIEW_NOT_PASS")
        findings = security.get("critical_findings")
        if not isinstance(findings, list) or findings:
            reasons.append("SECURITY_CRITICAL_FINDINGS_OPEN_OR_MISSING")
    return not reasons, reasons


def main(argv=None):
    argv = sys.argv if argv is None else argv
    root = Path(argv[1] if len(argv) > 1 else ".")
    try:
        health = json.loads((root / "FINAL-HEALTH-REPORT.json").read_text(encoding="utf-8-sig"))
        security = json.loads((root / "FINAL-SECURITY-REPORT.json").read_text(encoding="utf-8-sig"))
    except (OSError, ValueError, UnicodeError):
        print(json.dumps({"allowed": False, "blocking": ["CLOSURE_EVIDENCE_MISSING_OR_INVALID"]}))
        return 2
    allowed, blocking = review_closure_evidence(health, security)
    print(json.dumps({"allowed": allowed, "blocking": blocking}, indent=2))
    return 0 if allowed else 2


if __name__ == "__main__":
    raise SystemExit(main())
