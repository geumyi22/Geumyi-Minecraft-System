# Day 12.5 — Focused ActiveStore and GSC directory ACL result, 2026-10-11 KST

**Evidence:** operator-supplied private redacted `DAY12-PHASE5-DECISION-SHARE-ONLY-THIS.json`, generated `2026-10-11T03:09:03+09:00`. `synthetic=false`, `read_only=true`, `result=CAPTURED_FOR_HUMAN_REVIEW`; filter failures 0, errors 0. The underlying report and local private rule identity file have **not** been committed.

## Firewall factual scope
- Active network categories: Private + Public. All 3 ActiveStore firewall profiles enabled and set to default inbound Block; local rules allowed. Default Block is not proof broad Allow rules cannot match.
- 269 enabled inbound Allow rules scanned, **38** of them broad `Any` app / `Any` port / `Any` protocol and `Any` remote address. All 38 overlap an active profile; local policy source. **36** have `Any` local address and are tagged `HIGH_REVIEW`; **2** have redacted restricted local addresses and are tagged `SCOPED_REVIEW`.
- Profile split among the 38: Domain+Private=23, Domain+Private+Public=8, Any=7. Interface alias/type, service, and authentication/encryption filters were uniformly unconstrained by this collector for these candidates; don't read this as a complete effective WFP decision.
- `edge_traversal` among 38: `Block`=23, `Allow`=15. **CRITICAL:** EdgeTraversalPolicy=Block is not synonymous with Firewall Action=Block. All the examined rules have `Action=Allow`. Hence none of these 23 can be summarily dismissed as blocked incoming traffic.
- Broad rules may legitimately belong to OS, VPN, gaming, development or remote administration. Redacted IDs/names cannot prove necessity, overlap, publisher or maliciousness. **Do not disable or delete 36 or 38 rules in bulk.**

## GSC service and ACL factual scope
- GSC Host service account class: `LOCAL_SYSTEM`, running, auto-start.
- `GSC_PROGRAMDATA_DIR`, `GSC_RUNTIME_DIR`, `STATUSAGENT_RUNTIME_DIR` each have one inherited `BUILTIN_USERS` Allow ACE enabling create files/create directories with ContainerInherit; not grant Delete/DeleteChild/ChangePermissions/TakeOwnership in that ACE.
- The existing `server.json` file and StatusAgent 0.5.4 JAR were separately inspected earlier and no direct BUILTIN_USERS mutating Allow ACEs were reported on those **files**. The present three-directory ACEs do not by themselves establish overwrite of existing files or effective rights for a specific nonadmin token.
- Security question: a SYSTEM-privileged program consuming files created by standard users could be an integrity boundary; this requires a **specific trusted-load path**, effective token permissions, and updater/service account trace. No actual misuse or vulnerability is proven.
- Source spot-check `GSC/ServerCenter/cmd/setup/selfupdate_windows.go`: self-update uses `%ProgramData%/GeumyiServerCenter/Updates`, `Backups`, and `Staging/GSC` paths with embedded payload and a validation/rollback flow. Merely using ProgramData does not prove executing attacker-created content. No software change or full trust-boundary audit was performed.

## Decision and next narrowly scoped work
- Operator packet gives **better triage**, not a 12.5 security PASS; `security_verdict=OPEN_NOT_EFFECTIVE_WFP_PROOF`. Do not assert actual permitted remote attack paths from broad candidate matches alone.
- Preserve previous scoped LAN and tailnet negative TCP probes, 8/8 unauthenticated GSC 401, verified Java/Bedrock functionality, and the v3.1 six-owner-loopback private socket evidence as separately scoped observations; **no repeat required**.
- Rule necessity: use the already generated `PRIVATE-FIREWALL-RULE-IDENTITIES-DO-NOT-SHARE.json` **locally**, without publishing names, program paths, aliases, IP ranges or personal information. Classify trusted rule owners and possible duplicates; prepare a per-rule optional least-privilege proposal and rollback manifest before any change.
- Effective ACL: if later necessary, review a specific non-admin token's effective ability to create a file **without attempting file creation**, and trace service/updater read/execute paths; first secure exported ACL backups. No ACL inheritance changes merely because three inherited ACEs exist.
- **Do not** change the authoritative `FINAL-RELEASE-GATES.json`, `backend_ports_private=FAIL_UNVERIFIED_NATIVE_OWNER_ADDRESS`, `stable_release_allowed=false`, or any immutable closed-scope ledger IDs. The Other server was offline when the v3.1 6/6 private socket signatures were captured, so 8/8 never proven in that snapshot.

**Net conclusion:** 12.5 focused evidence capture completed; security risk disposition remains **OPEN**. No operational production changes authorized or made.
