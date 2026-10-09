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
