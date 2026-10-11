# Day 12.5 — Exact ACL target / preflight / rollback gate (2026-10-11)

**Decision: READ-ONLY PREFLIGHT READY FOR WINDOWS CI; PRODUCTION ACL APPLY NOT APPROVED.**
This document defines the specific objects and checks necessary to finish an operator-approved least-privilege change. It does **not** provide a blind live modification or assert security PASS. Both the firewall necessity review and strict 8-port OS listener/owner proof remain independent open gates.

## Source evidence (what is actually known)

- Operator's real 2026-10-11 11:44 KST DACL v4 JSON: linked **UAC-filtered administrator** token, not an independent standard-account token. It reports DACL add-file allowed on GSC root, GSC Runtime and StatusAgent Runtime, root add-directory allowed, and direct \`server.json\` write denied. This is not an actual create/overwrite test, nor a Windows mandatory-integrity-policy evaluation.
- Prior scoped live directory ACL inventory: the three directories each contain an inherited **BUILTIN_USERS (S-1-5-32-545)** Allow entry with creation rights. Existing \`server.json\` and Agent JAR had no *direct* BUITIN_USERS mutating Allow ACE observed. The service account was LocalSystem. Do not infer that a single ACE is the final effective-access decision.
- GSC source: Host default root is \`%ProgramData%\GeumyiServerCenter\`. The default Agent working directory is \`%ProgramData%\GeumyiServerCenter\Runtime\Agent\`. Host saves \`server.json\` and device state under root. Setup/updater uses \`Updates\`, \`Backups\`, \`Staging\GSC\`; Agent writes runtime logs and pid. An installer or scheduled task could use another token and must be accounted for.
- GSC source hardening is staged in **Draft PR #47** on branch \`security/day12-tempfile-acl-review-20261011\`. It does **not** modify installed GSC 4.5.1. Retain the scoped Windows CI evidence independently from on-host ACL proof.

## Exact first-class ACL review targets (paths are templates, verify actual expansion locally)

| Priority | Path relative to %ProgramData% | Write operations needing review | Proposed direction |
|---|---|---|---|
| P0 | \`GeumyiServerCenter\` | Create root-level config temp, pairing/device temp, update/cache folders | Remove only **unnecessary** ordinary-user file/subdir creation grants after dependency proof; retain SYSTEM/Administrators and legitimate read/traverse |
| P0 | \`GeumyiServerCenter\Runtime\` | Child directories and runtime writes | Restrict unnecessary ordinary-user creation, preserve Agent/GSC service requirements |
| P0 | \`GeumyiServerCenter\Runtime\Agent\` | Agent pid/log files and JAR reads | Restrict ordinary-user creation but preserve Agent's actual execution-token write needs |
| **Do not edit blindly** | \`GeumyiServerCenter\server.json\` | Host config read/write | Existing filtered-token direct WRITE_DATA was DENIED; preserve present ACL unless a verified defect |
| Dependency / no preapproved change | \`GeumyiServerCenter\trusted-devices.json\`, \`Updates\`, \`Backups\`, \`Staging\`, \`Staging\GSC\` | Pairing, signed-update metadata and rollback | Capture exact ACL, owner and inheritance to ensure hardening does not break update/restore |

Changing root inheritance may change the effective rights of every child, even if the planned grant adjustment sounds "root-only". No blanket \`/reset\`, \`/T\`, \`/remove:g *S-1-5-32-545\`, or explicit deny to BUILTIN_USERS is authorized. Administrators can belong to BUILTIN_USERS, so an overbroad explicit deny could also block administrator-run installers.

## Phase A: one-time, zero-production-mutation preflight (the ONLY currently authorized stage)

**Tool** (source under review):
- \`tools/day12/Day12_Phase5_ACL_Change_Preflight_READ_ONLY.ps1\`
- \`tools/day12/START_Day12_Phase5_ACL_Change_Preflight_READ_ONLY.cmd\`

Requirements: run on the actual Windows **server PC**, not client PC, after the focused Windows Safety CI verifies the tool. Do **not** run \`Set-Acl\` or \`icacls\` manually against GSC; this inspection must not change existing folder permissions. The tool self-tests and then:
1. Inspects the three exact directories, their %ProgramData% parent, and relevant child dependencies (JSON, trusted devices, Updates, Backups, Staging, Agent JAR).
2. Reads existing SDDL/owner/ACE/inheritance **locally** without exporting full path, account, SDDL, or credentials in the shareable report.
3. Reads GSC Host Windows service account **class**, rather than exporting service paths.
4. Creates **only an output folder** under the operator's \`%LOCALAPPDATA%\Geumyi-Day12-ACL-Preflight\`, setting that new output directory's ACL to a protected user/SYSTEM/Administrators scope. It does **not** change any production ACL. It may be blocked if the current user cannot protect the new output folder; that is a tool failure, not a GSC fault.
5. Stores two files: \`DAY12-ACL-CHANGE-PREFLIGHT-SHARE-ONLY-THIS.json\` (send this **only**) and \`PRIVATE-ACL-SDDL-SNAPSHOT-DO-NOT-SHARE.json\` (retain locally; never upload/share/commit).

**Evidence boundary:** this snapshot records the current ACL; it is **not** an \`icacls /save\` rollback archive, and provides **no proof of independent standard-user file creation or successful privileged service writes**. Missing folders, reparse points, unknown owners/permissions, or service identity mismatches block a change recommendation.

## Phase B: determine the exact targeted ACE diff — NOT YET DETERMINED

After reading redacted Phase A evidence, a private local administrator must determine:
- which actual ACE grants S-1-5-32-545 creation rights and whether it is inherited from the ProgramData parent, GSC root, Runtime parent, or explicitly set;
- any other user groups granting the same rights, and any authenticated-user, service-SID, AppContainer, group-policy, mandatory integrity or reparse boundary;
- the actual GSC Host account, StatusAgent launch account, installer/updater and scheduled maintenance identities, all necessary write paths;
- whether a distinct standard-user security token (not just the UAC-filtered admin token) can gain effective create/replace access;
- whether staged randomized-temp source PR #47 is included in a later **separately approved release**, or the running binary is still 4.5.1 with older temp save behavior.

Only then write an **exact target-relative change list** with current/desired SDDL fingerprints, original ACE principal SID, Allow/Deny/inheritance flags, operations to remove/retain, and precise rollback path. No ACE change may be applied on inferred group names alone. Preserve root/child read/traverse and updater/Agent functionality. A name like BUILTIN_USERS is not sufficient to remove all its rules.

## Phase C: protected pre-change backup + isolated rehearsal — BEFORE approval

1. In an administrator-controlled, access-restricted **separate output location**, capture targeted parent/child security descriptors and owner/inheritance as a private pre-change snapshot. Additionally create a **real** \`icacls /save\` DACL archive using exact target paths and their correct parent path context (and verify expected entries); save its SHA-256. The Phase A snapshot alone does not prove restorable fidelity.
2. Test snapshot/restore on a disposable Windows directory tree faithfully reproducing source inheritance. Confirm exact SDDL equality of affected objects after restore, and identify intentional differences in owner/SACL handling. \`icacls /save\`/\`/restore\` DACL operations are not a full owner/SACL or MIC backup.
3. Test a standard-user token (where available) versus the Host/Agent/updater service identities against the disposable tree, including clean authorized create/write/read and rejected unauthorized create/write; do not force-run executable content as SYSTEM from an untrusted directory.
4. Recheck old valid Host config, device pairing state, signed staging cache, Golden 4/4 protected backups, and no ongoing update jobs; do not regenerate or overwrite backups solely for this plan.
5. Produce a rollback rehearsal record and stop if pre/post descriptors differ unexpectedly or necessary identities lose access.

**Microsoft reference:** \`icacls /save\` persists DACLs for restore under a directory; \`icacls /restore\` needs the correct directory-relative context. \`/reset\` replaces DACLs with defaults and \`/inheritancelevel:r\` removes inherited ACEs; neither is a safe general repair. Reference: https://learn.microsoft.com/en-us/windows-server/administration/windows-commands/icacls

## Phase D: separate, explicit production approval and narrowly scoped apply

**NOT AUTHORIZED in this review.** Present the operator with a short exact specification before requesting approval:
- Exact object list, effective ACL owner/inheritance source, SID/ACE delta and fingerprint.
- Whether and why runtime/inherited BUILTIN_USERS create rights must change, and what standard-user rights remain.
- Rollback archive file/hash/path, a proven stage-only restore command, and the stop/rollback triggers.
- Whether GSC/StatusAgent/update activity can continue uninterrupted; if not, the exact authorized maintenance window and expected effect.
- Signed release relationship: source CI PASS is not installed GSC 4.5.1 and does not authorize an update.

Only apply the individually approved change on the actual host, without modifying ProgramData globally, unrelated processes, Paper/Velocity/Geyser, worlds, backup ZIPs, scheduled tasks, network, service account or firewall. Do not restart a service unless separately approved and players/update activity checked. Record only sanitized before/after summaries.

## Phase E: after-change verification and **mandatory rollback conditions**

The protected original ACL must be restorable before attempting any apply. After apply, check in this order:

1. **Identity and DACL:** exact approved target SDDL change and parent/child inheritance are as specified, no unrelated ACE changes; an independent standard-user test denies only unauthorized create/replace; SYSTEM/Administrators/Host/Agent/updater retain required rights. Confirm mandatory integrity restrictions where relevant.
2. **GSC:** Host service stays running, API authentication, device pairing persistence, control/snapshot/console, GSCM Android & desktop client connection all work.
3. **Agent/update:** StatusAgent heartbeat, status/logs, signed update manifest validation and **stage-only** dry-run pass. No actual new update/canary apply is authorized by this check.
4. **Server data:** all four server profiles and known-good backups remain intact; normal Java/Bedrock public ingress and backend routing work. No unnecessary four-server reboot or world restore.
5. **Evidence:** report approved change ID, exact changed object counts, status, rollback archive hash, redacted validation counters and user-accepted normal operation. Any missing proof stays OPEN.

**Immediate rollback trigger:** any unauthorized scope change, unexpected permission denial, GSC/Agent/pairing failure, failed update-staging or recovery metadata write, loss of management access, or service/game regression. Restore **only the approved ACL scope** from the previously verified private archive; do not touch game worlds/Golden backups, GSC binaries or firewall. Re-read exact SDDL and rerun the selected smoke tests. If restored SDDL or functionality diverges, stop, preserve logs and report manual recovery needed. Exit code 0 alone cannot certify rollback.

## Formal gates remain separate

- Phase 12.5 ACL: evidence collection complete, *effective least-privilege correction not deployed*.
- Phase 12.5 firewall: 15 Public-overlap broad allow rules still have no verified owner/necessity.
- Phase 12.10 exclusive private backend Java/RCON OS native owner/bind: still unverified for all 8 ports.
- \`FINAL-RELEASE-GATES.json\`: unchanged; strict signed auto-Stable and maintenance remain blocked.

**This is a readiness and safe process document, not an authorization or proof that production ACLs were successfully secured.**


## Updated real-host ACL source mapping — 2026-10-11 12:14 KST

Operator supplied **sanitized**, non-synthetic \`DAY12-ACL-CHANGE-PREFLIGHT-SHARE-ONLY-THIS.json\`. The private local original SDDL was **not** shared with GitHub, so an exact ACE diff/restore command **cannot** be derived in this PR yet.

| Role | Exists | BUILTIN_USERS create Allow ACE | Inherited | Direct Users write Allow ACE observed |
| --- | --- | --- | --- | --- |
| \`PROGRAMDATA_PARENT\` | yes | 1 | **no** | 1 |
| \`GSC_ROOT\` | yes | 1 | **yes** | 1 |
| \`GSC_RUNTIME\` | yes | 1 | **yes** | 1 |
| \`STATUSAGENT_RUNTIME\` | yes | 1 | **yes** | 1 |
| \`GSC_UPDATES\` | yes | 1 | **yes** | 1 |
| \`GSC_BACKUPS\` | yes | 1 | **yes** | 1 |
| \`GSC_STAGING\` | yes | 1 | **yes** | 1 |
| \`GSC_STAGING_CHILD\` | yes | 1 | **yes** | 1 |
| \`GSC_SERVER_JSON\` | yes | 0 | no | 0 |
| \`GSC_TRUSTED_DEVICES\` | yes | 0 | no | 0 |
| \`STATUSAGENT_JAR\` | yes | 0 | no | 0 |

All 11 objects were captured. Required target gaps 0; reparse targets 0; unresolved SIDs 0; GSC Host account class \`LOCAL_SYSTEM\`; **no existing production ACL or service was modified**. The preflight creates and ACL-protects **its own evidence output folder only**, not ProgramData/GSC. Independent standard-account token, mandatory integrity, actual file create/replace, and update rollback remain unproven.

**Revised change-scope decision:**
- Do **not** edit the explicit ACE on the real \`%ProgramData%\` parent. This may affect unrelated applications and Windows services.
- The **single proposed inheritance boundary** is the GSC **root directory**, but only if local private ACE detail confirms that root is the sole relevant source of create/write propagation to all sensitive descendants and the affected service/installer/updater identities retain necessary access.
- Model intended result as *preserve appropriate Users read/traverse ACEs, SYSTEM/Administrators/service writes; remove only unnecessary Users create/write on GSC root and inherited children*. This is a **provisional design**, not an executable ACE grant/removal instruction; exact rights, owner, inheritance flags and inherited descendant behavior must be checked privately.
- \`server.json\`, \`trusted-devices.json\`, and Agent JAR have **no observed BUILTIN_USERS write Allow ACE**. Do not alter their ACLs as part of an automatic fix.
- \`GSC_BACKUPS\` in this inspection refers to **GSC ProgramData update backup metadata/storage**, not the protected full Minecraft world Golden backups.
- Other local principals, explicit child ACEs and alternative access paths are not captured sufficiently by the aggregate counters; their absence must **never** be inferred.

**Disposable rehearsal:** \`tools/day12/ci/Day12_ACL_LeastPrivilege_Rehearsal_Windows_CI.ps1\` uses a GUID-scoped synthetic Windows fixture under GitHub runner temp, creates an explicit parent BUILTIN_USERS Allow and a GSC subtree, saves its original DACL with \`icacls /save\`, changes **only synthetic GSC root inheritance/grants**, validates parent untouched, Users read/traverse retained and synthetic descendant create rights removed, then restores with \`icacls /restore\` and checks DACL-only SDDL equality. The CI guard refuses non-runner/non-fixture execution and does not touch any real user machine. **CI result must be checked and recorded before declaring even the rehearsal successful.**

**Production permission gate remains CLOSED** pending a trusted on-host ACL backup archive with verified parent-relative restore context, private exact ACE mapping, independent standard-user effective right assessment and affirmative user approval specifying target/impact/window. This result **does not upgrade the formal phase-12.5, phase-12.10 or Stable gates**.
