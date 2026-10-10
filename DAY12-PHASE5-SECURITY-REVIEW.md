# Day 12 Phase 12.5 — Live Security Evidence & Decision Record

## 2026-10-11 — Focused ActiveStore and local identity review (newest evidence)

The earlier 2026-10-09 evidence below is retained as historical capture, **not the latest inventory**. Latest real-host read-only report (`DAY12-PHASE5-DECISION-SHARE-ONLY-THIS.json`, 03:09 KST) examined **269** enabled inbound Allow rules, with **38** broad Any-app/Any-port candidates: 36 local-address-any HIGH_REVIEW, 2 address-scoped. Private+Public network categories active, 3 profile defaults inbound Block, zero collection errors. GSC Host runs **LocalSystem** and all three GSC ProgramData/runtime directory targets have an inherited `BUILTIN_USERS` create-files/create-directories Allow ACE without observed delete/permission-change/ownership bits. Individual ACE declarations do not establish effective nonadmin token rights or a vulnerability. See [focused live report](DAY12-PHASE5-LIVE-FOCUSED-SCOPE-RESULT-20261011.md).

Subsequent **03:23 KST** local-only rule identity hint result (no rescanning, no policy change): all **38** paired rules were categorized by names into **22 Windows-feature hints, 11 unclassified, 3 gaming, 2 VPN/overlay**; review tiers **15 Public-overlap, 21 Private-focused, 2 locally address-scoped**; three scope-comparison groups of sizes 7,8,21. No actual rule necessity or WFP effect was proven, and similar names/scope do not authorize removal. Only the sanitized aggregate is committed; raw identities and paths remain private on operator PC. See [live rule identity result](DAY12-PHASE5-RULE-IDENTITY-LIVE-RESULT-20261011.md).

**Phase 12.5: evidence collection complete, effective-security approval OPEN.** No firewall/ACL mutation, no server restart or new user diagnostic justified solely by these count/name summaries. Formal Stable/Maintenance and canonical backend-port gate remain fail-closed.


Updated: 2026-10-09 06:43 KST  
Scope: **READ-ONLY** evidence and review. This is not permission to edit a running host, firewall, ACL, binaries, or backups.

## Verdict

- **Evidence collection:** CAPTURED. **Security gate:** OPEN / not PASS. **12.10 backend_ports_private:** canonical FAIL. **12.13 Stable release:** BLOCKED.
- The operator-provided `Day12-Rule-ACL-Review-20261009-064327.json` (private evidence, not committed) records `phase=12.5-acl-only`, `read_only=true`, `synthetic=false`, `result=CAPTURED_FOR_REVIEW`, `firewall_enumeration=NOT_EXECUTED_ACL_ONLY`, `acl_target_label_consistency=true`, `problem_count=0`, `mutation_performed=false`, `secrets_exported=false`.
- The previous 06:35 ACL report's target-name bug (`$Role` vs `$role` case-insensitive PowerShell collision) is corrected **and verified in the 06:43 live output**. NTFS `DeleteSubdirectoriesAndFiles`/`delete_children` is now reported separately.

## Exact operator ACL findings — 06:43

| Target | Captured ACEs | Inheritance protected? | BUILTIN_USERS mutating Allow ACE | BUILTIN_USERS create file / directory | BUILTIN_USERS Delete / DeleteChild / ChangePermissions / TakeOwnership |
|---|---:|---|---:|---|---|
| `GSC_PROGRAMDATA_DIR` | 5 | No | 1 | Yes (directory, ContainerInherit) | All reported false |
| `GSC_SERVER_JSON` | 3 | No | 0 | No | All reported false |
| `GSC_RUNTIME_DIR` | 5 | No | 1 | Yes (directory, ContainerInherit) | All reported false |
| `STATUSAGENT_RUNTIME_DIR` | 5 | No | 1 | Yes (directory, ContainerInherit) | All reported false |
| `STATUSAGENT_054_JAR` | 3 | No | 0 | No | All reported false |

Caveats:
- These flags describe **individual Allow ACEs** for coarse principal groups, not every actual access token's effective NTFS rights. All five objects have ACL inheritance enabled (`protected_acl=false`).
- For a **directory**, the reported `write_data_or_create_files` / `append_data_or_create_dirs` describe creation rights in that directory. They do **not** automatically mean direct overwrite permission on pre-existing `server.json` or JAR file contents. The two file ACLs themselves did not grant `BUILTIN_USERS` mutating Allow.
- Ordinary `BUILTIN_USERS` ACEs in all three directories report **`delete_children=false`**, as well as `delete=false`, `change_permissions=false`, and `take_ownership=false`. Admins and SYSTEM have broader rights.
- Possible risk: unprivileged local users may be able to **create new files/directories inside GSC runtime areas**. Whether this is acceptable depends on host operating account, update workflow, service account, directory use and effective access; no successful actual write/create action was attempted or proven. **Do not infer a proven overwrite, privilege escalation or compromise**.

## Prior firewall and GSC API evidence preserved, not re-run

- 06:13: active inbound firewall inventory **268** rules, 0 rule-processing errors; target-specific Allow includes Java TCP 25565/25566, Bedrock UDP 19132/19133, and GSC API TCP 8787 LocalSubnet. These named rules are not the same as the broad Any-port Allow candidates.
- 06:21: ActiveStore **266** enabled inbound Allow rules reviewed, **38** broad Any-program / Any-port candidates, all active-profile-overlapping; default inbound Block on Domain/Private/Public, but Allow rules may override the default.
- 06:35: broad rules classified from **names only**: 33 UNCLASSIFIED, 3 GAMING_HINT, 2 VPN_OR_OVERLAY_HINT; **15 HIGHER_REVIEW** due to Any/Public profiles. Name hints are **not identity, signature, or rule necessity verification**, especially on localized Windows installations.
- ~06:25: operator reported second-PC LAN TCP 8787 reachable; unauthenticated `GET /api/v1/info` returned **HTTP 401**. This confirms the inspected API endpoint rejected missing credentials from that vantage, not that all API routes or public internet are covered.
- Separate-PC Java/RCON LAN proof was previously **3/3 expected Java public TCP reachable and 0/8 internal/RCON ports reachable** from the tested LAN path. This does not prove private binding addresses or Tailscale/public-internet exposure.

## Remaining security decisions (do not automate)

1. **ACL least privilege — deferred for approval.** Determine the exact Windows GSC host service account, updater/installer identity, maintenance workflows, parent inheritance and access tokens. A potential future hardening strategy is to remove unneeded ordinary-user directory creation rights **only after** a separate ACL backup, preflight of service/updater permissions, explicitly approved change window and rollback plan, plus real GSC/GSCM/backup E2E. Do **not** remove `BUILTIN_USERS` inheritance or modify files from this evidence alone.
2. **Broad firewall allows — unresolved.** The 33 UNCLASSIFIED rules must be mapped to identities and purposes **privately** before recommending targeted rule removal. Current sanitized heuristics cannot support disabling any particular rule. Existing local network functionality, Tailscale and remote administration must be preserved.
3. **Canonical backend binding — independent block.** 12.10 verifier remains 18 PASS / 1 FAIL (`backend_ports_private`). Nonreaching LAN probes are not a substitute for listener-address evidence. Do not bypass the verifier.
4. **Release gating.** Do not change `FINAL-RELEASE-GATES.json`, declare Phase 12.5 PASS, edit production firewall/ACL, reboot servers, delete legacy Agent JARs, or promote Stable. 12.11 E2E and 12.12 soak still pending.

## Operational boundary and evidence provenance

Original JSON reports remain private to the operator/ChatGPT conversation. This repository contains only sanitized findings, file roles, version numbers, procedural notes, and fail-closed conclusions. The live system was not changed by this review. All data-dependent conclusions here are scoped to the captured read-only reports and operator-reported HTTP/TCP results.
