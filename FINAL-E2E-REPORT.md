# Day 12 — Final Live E2E Report

Status: **PENDING LIVE EXECUTION**

This report is intentionally not marked PASS until the real server PC, Java client, Bedrock client and GSCM device flows are executed.

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
