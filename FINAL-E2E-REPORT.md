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
