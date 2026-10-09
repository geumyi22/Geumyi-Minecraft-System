# Day 12 — Final Live E2E Report

Status: **PENDING LIVE EXECUTION**

This report is intentionally not marked PASS until the real server PC, Java client, Bedrock client and GSCM device flows are executed.

## Live operator safety rules (prepared, NOT executed)

- All checks below remain unchecked until the **user actually executes** them on the server PC, Java/Bedrock clients and GSCM devices; CI and saved configuration evidence do not replace game-client E2E.
- Production reboot, intentional server shutdown, forced-loss/crash recovery, RCON stop, restore/apply/rollback and device-token revocation are **service-changing actions**. Require an explicit user-approved maintenance window, preserve the existing 4/4 Golden checkpoints and known-good artifacts, check active players and document rollback before executing them.
- Run deliberate **unexpected-loss or destructive recovery simulations on disposable/staging**, not by killing production Java processes or modifying live world data. Production restore must not be initiated just to check a box; use safe preflight or an explicitly approved disposable restore target.
- Gate status: Day 12.10 canonical `backend_ports_private` remains unresolved after real-host loopback-app-start logs 8/8; do not bypass by interpreting the log as contemporary OS socket proof.
- The 12.12 soak monitor was hardened in source to compare **name+PID+process-start-time** and refuse overwriting Start/End reports. Its CI synthetic PASS is not a real soak. Do not begin an 8–12 h live soak unless the operator has agreed to the planned monitoring window and 12.11 prerequisites.

## Readiness update: Playground lifecycle proved, live-client E2E still pending (2026-10-10)

- One limited **actual** GSC graceful Playground restart job succeeded under zero players, protected full backup and zero active jobs; Playground was ONLINE before and after. This is **only a partial lifecycle observation**, not Java/Bedrock/GSCM gameplay E2E and not proof of exclusive Java/RCON bind. Do not check the reboot, all-server or client testboxes below.
- The immediate post-restart Windows native listener check CAPTURED but did not see Playground Java 25571 or RCON 25576. Day12.10 strict security gate still FAIL.
- Safe low-impact client checks (Java→Lobby→Wild/Playground, Bedrock→Lobby→Wild/Playground, return to Lobby and verify previous location, GSCM realtime status/reconnect without modifying server) can be prepared separately, but must not be marked PASS until performed by user on real clients. Tests affecting services, saves, restore, credentials or backups remain gated.
- No further Playground restarts or repeating Windows native TCP inventory until a new substantive root-cause/attestation method is available.

## Operator-reported Java pre-E2E — 2026-10-10 KST (partial, non-release-grade)

- After being asked to test the real Java client via the public entry, the operator replied **"됨"** to the four-step checklist: public entry to Lobby; Lobby -> Wild -> Lobby; Lobby -> Playground -> Lobby; and previous-location preservation when re-entering Wild and Playground.
- Record as **OPERATOR_REPORTED_PASS** for these exact Java client steps only. No independently attached client log, timestamped screenshot, or machine-generated E2E report was provided with this acknowledgment.
- Other backend was explicitly excluded because it was OFFLINE in the latest available prior fleet snapshot. **Lobby -> Other remains untested**, as do Bedrock and GSCM, Windows reboot, operations and soak.
- This is a safe pre-E2E functional observation, **not** the release-grade 12.11 Java E2E PASS: the 12.10 mandatory `backend_ports_private` gate is still FAIL, and the complete four-backend real-client path is pending.
- **Next operator action:** Bedrock client public entry -> Lobby -> Wild / Playground -> Lobby -> verify return and previous-location behavior. Do not expose backend ports, change firewall, or restart servers merely for this check.

## Operator-reported Bedrock pre-E2E — 2026-10-10 KST (partial, non-release-grade)

- Operator replied **"됨"** after the four-step Bedrock client checklist: public Bedrock entry -> Lobby; Lobby -> Wild -> Lobby; Lobby -> Playground -> Lobby; and previous-location preservation on re-entry.
- Record as **OPERATOR_REPORTED_PASS** for these specific Bedrock paths only. No client-generated log, screenshot or independent verification accompanied the reply.
- Other was excluded, as it was OFFLINE in the latest prior known fleet snapshot. Lobby -> Other, identity/permission regression, complete Java/Bedrock full E2E, operations and GSCM remain pending.
- This is **not** release-grade 12.11 PASS. Mandatory Day 12.10 `backend_ports_private` remains FAIL; do not promote Stable or mark Day 12 complete.
- **Next safe operator step:** GSCM real-device read-only connectivity/reconnect, real-time fleet status and console-view check. Do not revoke/delete/re-pair devices, restart servers or apply updates for this basic check.

## Operator-reported GSCM basic pre-E2E — 2026-10-10 KST (partial, non-release-grade)

- Operator replied **"됨"** after the actual-device GSCM checklist: GSC connected and displayed fleet state, Wild/Playground/Lobby state matched observed operation, live status refreshed, connection survived app termination/relaunch, and console read/view worked.
- Record **OPERATOR_REPORTED_PASS** limited to these five listed GSCM **read-only/basic connectivity** checks. Device platform (Android/iOS) and attached device-side logs were not supplied, so do not claim both platforms independently verified.
- This does **not** verify GSCM mutation flows (start/stop/restart, backup/restore, updates, revoke/delete/re-pair) or all server profiles. In particular Other remained excluded from prior Java and Bedrock pre-E2E checks.
- Day 12.10 mandatory `backend_ports_private` is still **FAIL**. Full 12.11 E2E and 12.13 Stable release are still **PENDING/BLOCKED**.
- **Next:** plan safe partial operations checks and independent resolution of runtime backend bind attestation; avoid repeating the successful basic client checks or triggering production destructive operations.

## Operator-reported GSC console command check — 2026-10-10 KST (partial, non-release-grade)

- Operator replied **"됨"** after being asked to execute the read-only `list` Minecraft server console command through **GSC PC management UI** for both Wild and Playground and confirm that the command responses displayed normally.
- Record **OPERATOR_REPORTED_PASS** for **Wild and Playground GSC console `list` command-and-response only**. This supports partial console/RCON functionality but does not separately identify which transport path GSC used or prove all RCON operations, auth policy, console subscriptions, or other backend behavior.
- No screenshots, machine-readable command transcript or standalone transport check accompanied the acknowledgment. Lobby/Other console checks and deliberate server-state transitions remain pending.
- Day12.10 `backend_ports_private` still FAIL; 12.11 final E2E and Stable remain blocked.
- Next scoped pre-E2E: Other backend preflight in GSC (ONLINE/OFFLINE, no active update or job and safe-start readiness); if safe, bring it online through normal GSC action without force-start, then test Lobby <-> Other using Java and Bedrock clients. No server security, firewall or restore mutation is authorized by this acknowledgment.

## Operator-reported Other backend client check — 2026-10-10 KST (partial, non-release-grade)

- The operator replied **"됨"** after being asked to verify that the Other backend can be started when safe and that **both Java and Bedrock** clients can move **Lobby -> Other -> Lobby** and return to their **previous Other position** on re-entry.
- Mark **OPERATOR_REPORTED_PASS** for the specified Other client routing and last-location behavior. Whether Other needed starting or was already ONLINE was not separately stated; do **not** infer that the start-job/lifecycle path was tested from this acknowledgment alone.
- Combined operator acknowledgments now cover Java and Bedrock Lobby <-> Wild, Playground, Other and previous-position return, basic GSCM connectivity/status/console view, and GSC console `list` for Wild/Playground. These are positive **operator reports**, without independent device-side trace artifacts.
- Remaining test scope: runtime `backend_ports_private` security attestation (last canonical final verifier 18 PASS / 0 WARN / 1 FAIL), full operations/backup-restore/update and startup/reboot/offline E2E, real-device GSCM mutating actions, soak and release closure. These items are **not** implicitly PASS.
- Safe next user step: inspect GSC **Backup/Recovery** protected backup inventory and last verification status **read-only**; do not create, overwrite, delete or restore backups to collect this simple GUI observation. Protected Golden 4/4 was already separately verified earlier.

## Operator-reported GSCM remote Other console — 2026-10-10 KST (partial, non-release-grade)

- Operator responded **"됨"** after being instructed to open the **Other** server's console in the **GSCM mobile app**, execute the read-only Minecraft `list` command, and confirm that the response displayed successfully.
- Record as **OPERATOR_REPORTED_PASS** for the mobile GSCM **Other console command-and-response** flow only. The response did not include a command transcript or proof of any independent RCON transport, so do not generalize it to every remote mutation or all server consoles.
- Java/Bedrock Other routing and existing GSCM basic read-only checks remain separately operator-reported; Windows host reboot, backup/restore, update/rollback, GSCM credential/device lifecycle and long-duration soak still pending.
- The canonical Day 12.10 `backend_ports_private` check remains **FAIL** (last live verifier 18 PASS / 0 WARN / 1 FAIL). No Stable/Maintenance promotion is allowed.
- Next non-disruptive mobile coverage: check **GSCM backup list and protected/GOLDEN indicators** without running backup, restore, delete, or unprotect actions. Prior host-side protected Golden 4/4 evidence already exists; no new backup generation is needed.

## Operator-reported GSCM protected Golden backup inventory — 2026-10-10 KST (read-only, partial)

- Operator replied **"됨"** to the GSCM **Backup/Protection/Recovery** menu read-only checklist: list visible for **Wild / Playground / Other / Lobby**, and the four corresponding **Golden backups displayed as protected**.
- Mark **OPERATOR_REPORTED_PASS** for mobile UI **inventory visibility and protection indicators** only. No new archive was created, no bytes rehashed, no actual backup recovery/restore was attempted and no independent on-device screenshot/report was provided.
- Prior server-PC Golden 4/4 verified backup evidence remains separate; do not count UI indication alone as new integrity verification or as protection against failed restoration.
- Mandatory Day 12.10 `backend_ports_private` remains **FAIL** (last canonical 18 PASS / 0 WARN / 1 FAIL); Day 12.11 full E2E, 12.12 soak, Final Stable and irreversible cleanup remain **BLOCKED/PENDING**.
- Follow-up should verify the restore **preflight only**, on a safe path confirmed in source/UI before instructing the operator. **Do not trigger real restore, remove protection, delete backups, or interrupt live servers.**

## Operator-reported GSC updater status UI — 2026-10-10 KST (read-only, partial)

- Operator replied **"됨"** after viewing the **GSC PC Update Management** screen and checking: current version is displayed, update status displays normally, and no in-progress or failed update jobs appear.
- Mark **OPERATOR_REPORTED_PASS** for **UI visibility and the absence of visible pending/failed work at the observation time** only. No exact version string or machine-generated updater API status was supplied in this turn: do not claim a newly verified exact build number, nor successful update apply/rollback.
- No update, install, rollback or server configuration mutation was requested or performed for this check.
- Day 12.10 mandatory `backend_ports_private` remains **FAIL** (canonical 18 PASS / 0 WARN / 1 FAIL). Full release-grade 12.11 operations/reboot E2E, 12.12 soak, final Stable and cleanup remain **PENDING/BLOCKED**.
- Pending recovery validation must be limited to restore **preflight** until a controlled maintenance window and disposable target are explicitly arranged; never restore over production as a test.

## Operator-reported Other backup retention preview — 2026-10-10 KST (read-only)

- The operator replied **"됨"** to the exact GSC PC **Protection/Recovery → Other → retention preview** checklist and confirmed the **protected Other Golden backup was not included in deletion candidates**.
- Record **OPERATOR_REPORTED_PASS** for the **Other profile's dry-run/preview protected-exclusion behavior** only. This does not independently verify all four profiles' preview results, execution-path safety, backup ZIP integrity or restore capability. No machine-readable retention preview was attached.
- The user was specifically instructed **not** to click retention apply; do not claim any backup moved, modified or deleted. Prior four-server Golden backup SHA-256 verification and mobile protection UI observation are separate evidence.
- Source `buildBackupRetentionDryRun` in `v4_backup_actions.go` skips `Protected` and checkpoint items, supporting the intended safe behavior but not upgrading this operator UI acknowledgment to a full production retention-apply test.
- Existing Day 12.10 `backend_ports_private` **FAIL** (18 PASS / 0 WARN / 1 FAIL canonical), overall Day 12.11 final release-grade E2E **PENDING**, 12.12 live soak **PENDING**, 12.13 Stable **BLOCKED**.
- **Next:** avoid repetitive routine UI acknowledgments. Focus assistant-side source/synthetic validation and a materially different runtime bind-attestation plan; ask the operator only when a genuinely new, scoped host-side proof or maintenance operation is necessary.

## 2026-10-10 04:06 KST — Real Windows WFP audit probe outcome (NO INDEPENDENT BIND PROOF)

- User supplied `Day12-WFP-Bind-20261010-040617.json` from the actual server PC. This is a non-synthetic read-only report (`synthetic=false`, `mutation_performed=false`) with `result=UNAVAILABLE`, `error_category=AUDIT_RECORDS_UNAVAILABLE_OR_ACCESS_DENIED`, `event_count=0`, `process_generations_seen=11`, `query_truncated=false`.
- All **8** private Java/RCON target entries returned `NO_CURRENT_PROCESS_EVENT` (0 listen, 0 bind). Thus **no event-time listener address or owner was proved**; zero evidence does not indicate ports were exposed, offline or isolated.
- Original WFP reader's catch block conflates no matching Security events, authorization failure, process inventory error and invalid query. It cannot establish a specific root cause from this report. An updated classifier is under Windows synthetic CI; user should **not rerun the original script**.
- Canonical `backend_ports_private` remains **FAIL**; final 12.11 release-grade E2E, 12.12 soak and 12.13 Stable remain **PENDING/BLOCKED**. No Windows audit-policy changes, firewall changes or production restarts were authorized.

## Prerequisites

- [ ] Phase 12.0 Golden Baseline + protected Golden backups PASS
- [ ] Phase 12.3 health report has no mandatory FAIL
- [ ] Phase 12.5 security review has no unresolved critical finding
- [ ] Phase 12.7 known-good cache exists and verifies
- [ ] `Geumyi_Final_Verification.cmd` has mandatory FAIL=0 before live-client tests

## 12.11 Server-PC reboot gate

- [ ] Windows reboot
- [ ] GSC Host service returns healthy
- [ ] three Velocity startup tasks active
- [ ] Wild / Playground / Other / Lobby expected lifecycle state
- [ ] no duplicate/orphan process
- [ ] no unsafe update transaction

## Java real client

- [ ] public alias -> Lobby
- [ ] Lobby -> Wild
- [ ] Lobby -> Playground
- [ ] Lobby -> Other
- [ ] `/lobby`
- [ ] last-location restore for each backend

## Bedrock real client

- [ ] public Geyser entry -> Lobby
- [ ] Lobby -> Wild / Playground / Other
- [ ] return to Lobby
- [ ] identity/permissions remain correct

## Operations

- [ ] intentional stop -> OFFLINE
- [ ] unexpected loss -> RECOVERING -> recovery
- [ ] start / stop / restart
- [ ] console / RCON
- [ ] schedule
- [ ] backup + verify
- [ ] restore preflight/checkpoint/restore/health/rollback safety path
- [ ] update dry-run/apply/rollback path as applicable

## GSCM

- [ ] connect/reconnect
- [ ] realtime + HTTP reconciliation
- [ ] start/stop/restart/console
- [ ] backup/protection/restore preflight
- [ ] update status/control
- [ ] revoke -> restore
- [ ] delete -> re-pair

## Result

**PENDING LIVE**

No assistant-side real-client/device execution is claimed.
