# Day 12.5 — Local-only firewall rule identity triage live result

**Operator real-host evidence:** redacted `DAY12-PHASE5-RULE-TRIAGE-SHARE-ONLY-THIS.json` generated **2026-10-11 03:23:59 KST**, `synthetic=false`, `read_only=true`, `result=IDENTITY_HINTS_COMPILED_FOR_LOCAL_HUMAN_REVIEW`. This report contains no rule names, executable paths, IP addresses, service identities or secrets. The local private CSV **must not** be committed.

## Findings

- The **38** broad Any-program/Any-port Allow rules from the previous Phase5 read-only capture were paired and categorized locally, **without rescanning firewall, ACLs, LAN or GSC**. Pairing validation and script self-test succeeded on the user's Windows PC; this establishes local-script operation, not actual WFP policy or owner authenticity.
- **Priority:** 15 `P1_PUBLIC_PROFILE_REVIEW` (candidate ordinals `4,5,6,7,8,9,12,18,20,22,24,28,31,34,36`), 21 `P2_PRIVATE_PROFILE_REVIEW`, 2 `P3_LOCAL_ADDRESS_SCOPED_REVIEW`. These are **review tiers**, not attack severity classifications. Ordinals are **not** Windows firewall rule IDs.
- **Name-only hints:** 22 `WINDOWS_FEATURE_NAME_HINT`, 3 `GAMING_NAME_HINT`, 2 `VPN_OVERLAY_NAME_HINT`, 11 `UNCLASSIFIED_NAME_ONLY`. No `human_confirmed_rule_necessity` evidence (0). A Windows-feature label cannot prove trusted vendor, service need or safety. Unclassified cannot prove maliciousness.
- Three exact-selected-field comparison groups have more than one rule, with sizes 7, 8, and 21. This is **similar-scope evidence only**; it does not prove redundancy, effective rule action, Windows Filtering Platform priority, or safe deletion. Effective WFP and NTFS token permissions were **not proven**.
- **Safety:** `firewall_rules_modified=0`, `filesystem_acls_modified=0`, `minecraft_services_modified=0`. No service restart, network probe or world/backup changes.

## Decision

**Phase12.5 operational data collection and local identity-hint grouping are complete.** Final security approval remains **OPEN**, because 0/38 rule needs have been human-verified and ActiveStore inventory is not an effective WFP packet-level assessment. GSC Host still runs as LocalSystem and three GSC directories retain an inherited BUILTIN_USERS create-allow ACE from prior capture. These facts do **not** establish malicious rule behavior or a privilege escalation.

Use the **already-generated** local `LOCAL-RULE-IDENTITIES-REVIEW-DO-NOT-SHARE.csv` to map the 15 Public-overlap candidates to trusted function and actual necessity. No full firewall rescan, rule disable, ACL change, production restart or rerun of accepted LAN/Bedrock tests. Any further user action must have a specific necessity beyond name heuristics.

12.10 earlier scoped 6/6 online loopback listener signatures remain accepted as bounded evidence only; Other was offline in that snapshot. `FINAL-RELEASE-GATES.json` unchanged: `backend_ports_private=FAIL_UNVERIFIED_NATIVE_OWNER_ADDRESS`, `stable_release_allowed=false`, `maintenance_allowed=false`.
