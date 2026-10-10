# Day 12.5 — Local-only rule-identity triage, 2026-10-11

## Already confirmed real-host evidence

- Operator supplied `DAY12-PHASE5-DECISION-SHARE-ONLY-THIS.json` (`2026-10-11T03:09:03+09:00`, non-synthetic read-only, zero errors). Active network categories Private + Public; firewall defaults inbound Block. 269 active inbound Allow reviewed; **38** Any application/Any port candidates, 36 HIGH_REVIEW with local address Any, 2 locally scoped. All overlap an active profile. This is candidate inventory, NOT a verified WFP packet decision or exploit.
- These 38 have 23 `Domain, Private`, 8 `Domain, Private, Public`, 7 `Any` profile rules. Thus **15** Public-overlapping candidates merit earliest manual identity review. The 15 candidate numbers (relative to that exact report) are: `4,5,6,7,8,9,12,18,20,22,24,28,31,34,36`. IDs are only ordinal labels, NOT firewall rule identities.
- GSC Host service is LocalSystem. Group `BUILTIN_USERS` has inherited file/directory creation Allow in three GSC runtime-related directories; no Delete/DeleteChild/ChangePermissions/TakeOwnership in captured ACEs. Existing server.json and Agent JAR direct ACEs did not grant group mutating Allow. Do not assume direct file overwrite, effective nonadmin ability, or an actual privilege escalation.
- 12.10: v3.1 showed loopback, Paper-owned nonstandard TCP state 0 listener-signatures for 6/6 online game/RCON sockets, not Other's offline pair. Canonical eight-port proof remains blocked.

## Work executed without interrupting the operator

Built an independent, Windows PowerShell 5.1-targeted, **non-elevated read-only local identity helper**: `Geumyi-Day12-Phase5-RuleIdentity-LocalOnly-READ-ONLY.zip` distributed through the conversation. Contents:
- `Day12_Phase5_Rule_Identity_Triage_READ_ONLY.ps1` and `Start_Day12_Phase5_Rule_Identity_Triage_READ_ONLY.cmd`, plus `README-KO.txt`.
- Instead of rescanning Windows firewall, reads the **already generated paired JSONs** from `Desktop/Geumyi-Day12-Phase5-Decision-READONLY/`:
  `DAY12-PHASE5-DECISION-SHARE-ONLY-THIS.json` and local-only `PRIVATE-FIREWALL-RULE-IDENTITIES-DO-NOT-SHARE.json`.
- Validates count, ordered candidate numbers, each rule profile and local/remote address scope match. On mismatch, fails closed; does not generate unsafe verdicts.
- Uses *name/group hints only* (Windows/gaming/VPN/virtualization/Minecraft/remote mgmt/discovery/unknown); **never claims publisher authenticity or need** from string matching. Separates 15 Public-overlap, 21 remaining unrestricted-local, 2 locally scoped candidates. Potential exact-scope group duplicates are review hints, NOT redundant-rule proofs.
- Creates a **private local CSV** with rule names, paths and raw IP scope (DO NOT SHARE), alongside `DAY12-PHASE5-RULE-TRIAGE-SHARE-ONLY-THIS.json` with aggregate counts, category hints and anonymous ordinal IDs only. Neither re-enumerates policy nor changes anything.
- Script has `-SelfTest` invoked first by CMD; PowerShell 5.1 **real execution not yet tested** by GPT-6. Static source scan (no firewall-mutating or service commands), three-file ZIP byte integrity and structure checks performed locally. Synthetic in-script test expected to gate host processing; do not claim it executed on Windows before user runs.

## Guardrails

- No removal of broad rules, inheritance change, server restart, Windows build rollback, network scan, Golden/backup/pack changes.
- Prior accepted Java/Bedrock functionality and LAN/tailnet controls not to be re-run.
- 12.5 remains security OPEN; formal `backend_ports_private=FAIL_UNVERIFIED_NATIVE_OWNER_ADDRESS`; Stable and Maintenance remain BLOCKED.
- A rule/ACL change, if ever justified, requires a private identity+necessity review, backup, rollback and explicit operator-controlled window.
