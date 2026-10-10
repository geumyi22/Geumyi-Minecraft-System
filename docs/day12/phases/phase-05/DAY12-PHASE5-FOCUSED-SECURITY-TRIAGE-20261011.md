# Day 12.5 — Focused live security triage decision (2026-10-11)

**Source basis:** `DAY12-PHASE5-SECURITY-REVIEW.md` 2026-10-09 verified host data; `DAY12-FINAL-ONECLICK-OPERATOR-EVIDENCE-20261011.md` confirms no later ACL/Firewall policy change; 2026-10-11 live v3.1 state-0 listener evidence at `DAY12-CLAUDE-V31-LIVE-STATE0-EVIDENCE-20261011.md`.

## Already captured; do not repeat
- Five NTFS target ACL inventories: `GSC_PROGRAMDATA_DIR`, `GSC_RUNTIME_DIR`, `STATUSAGENT_RUNTIME_DIR` each have one inherited `BUILTIN_USERS` mutating Allow ACE with file/directory creation bits, **not** observed DeleteChild/Delete/TakeOwnership/ChangePermissions; `GSC_SERVER_JSON` and `STATUSAGENT_054_JAR` have **zero** group mutating Allow ACEs. These observations are ACE declarations, not service-token effective access or ability to overwrite specific files.
- Active firewall collection: 38 enabled inbound Any-app/Any-port Allow **candidates**, 33 of them name-category unclassified, 15 earlier name/profile heuristic higher-review. Existing scan indicates active profiles and some filter constraints; a candidate is **not** proof of unrestricted access or an unnecessary rule.
- Existing remote 8787 unauthenticated HTTP 401 and scoped private-port TCP negatives with public-positive controls remain accepted, not re-run.
- v3.1: 6/6 private TCP sockets belonging to three currently online Paper servers have an IPv4 loopback owner-matching state-0 signature; Other server is offline. This materially improves 12.10 evidence but does not automatically satisfy canonical 8-port or WFP security gates.

## Focused new evidence only
One optional Windows server-PC **read-only** triage script `Geumyi-Day12-Phase5-Focused-Review-READ-ONLY.zip` has been prepared in the ChatGPT conversation. It is **not** a production patch. It may be run once to confirm which broad candidate rules remain unconstrained after active profile, local/remote address, service, interface and authentication scopes, and what GSC service account classes and directory ACEs are present. The parser/classification SelfTest is bundled; Windows host run remains **NOT EXECUTED** until operator tests.

- Only `DAY12-PHASE5-DECISION-SHARE-ONLY-THIS.json` is safe to share in conversation. A separately written `PRIVATE-FIREWALL-RULE-IDENTITIES-DO-NOT-SHARE.json` includes local rule display names, program paths and address details and must **not** be uploaded, committed or circulated.
- HIGH_REVIEW prioritizes closer human evaluation only; NOT an effective Windows Filtering Platform (WFP) access decision. No automated disabling, permission removal, service restart, world/backup edit or production port scan. Check native exit status; partial output is not PASS.
- If firewall rule and ACL details are already available to the operator locally, do not repeat comprehensive collection; use them instead.

## Decision / safe next steps
1. Identify whether the 38 broad rules are Windows features, VPN/remote management, game-related or unrelated; only then document necessity/risk, preserving privacy. An unknown display name does not prove malware.
2. For ACL, determine the actual running GSC/agent/updater account and effective access to the three directories. Directory child creation rights can be an abuse surface, but existing evidence does not show file overwrite or privilege escalation.
3. Never change firewall/ACL without explicit operator acceptance, exported policy+ACL rollback artifacts, remote management preservation, and post-change GSC/GSCM/Java/Bedrock health checks.

**Protected state unchanged:** Phase 12.5=OPEN/REVIEW; `backend_ports_private=FAIL_UNVERIFIED_NATIVE_OWNER_ADDRESS`; `stable_release_allowed=false`; `maintenance_allowed=false`. No official 14 closed scoped evidence IDs changed.
