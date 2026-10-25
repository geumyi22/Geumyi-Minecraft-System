# GSC 4.5.2 Canary→Canary hotfix — stage-only, no live change

Status: **experimental / Draft PR #57**. The operator previously completed a live GSC service-only opt-in. The first Wild Velocity direct-control cutover disconnected Wild and failed to start GSC-owned Velocity. A manual restore successfully re-enabled and requested start of the original Wild Windows Scheduler task; the operator has since reported it running and showed an actual player connection in the Velocity log. **Never mark direct-management migration complete: it remains 0/3.**

## Decision

Keep all three original Velocity tasks in charge of production for now. No immediate need to migrate Velocity merely because a lot of development time was invested. Focus on stable GSC Host functionality and safer operations.

A Windows Scheduler 5-second probe timeout was found as a likely cause of false-negative migration observation, but the live incident could also have involved a private receipt validation failure. Code adds a 15-second bounded probe and sanitized distinction between Scheduler observation and cutover receipt verification. This is **not** validated as a live repair yet.

## Existing Canary must not use the old swap

The original `Run_GSC452_Host_Swap_WITH_AUTO_ROLLBACK_ADMIN.cmd` expected the running Host to be GSC v4.5.1 and prepared a private journal for the first 4.5.1→4.5.2 swap. It must **never** be rerun on an already-running 4.5.2 Canary. The previous Canary binary, its hash receipt, service-specific `REG_MULTI_SZ` opt-in and both original recovery journals are the rollback evidence; they must not be overwritten.

## New stage-only process

The `GSC452_Host_Canary_Hotfix_STAGE_ONLY.ps1` script has two modes:

- `Plan` (default): examines the existing GSC Host service and process identity, original Canary binary hash, first-swap and opt-in recovery journals, protected folder ACLs, exact service-only opt-in, no global machine opt-in, three Running/Enabled legacy Velocity tasks, uncommitted receipts, absent managed owner markers, auto-start backend ports, healthy Canary local API, and SHA-256 of the newly CI-built image. No changes.
- `Stage` (attended confirmation): runs the same checks, then creates *only* a separate protected `VelocityManaged/CanaryHotfix-R2-20261025` directory with the new image, checksums and an immutable stage receipt. Cannot overwrite a preexisting stage. It never installs the binary and never stops/starts the Host, tasks, JVM, or Paper.

The scripts are included in the new `GSC452-Velocity-CANARY-Host-NO-INSTALL` CI artifact. The artifact's `BUILD-REVISION.txt` ties it to the originating GitHub revision. A checksum file in the same artifact protects accidental corruption but is not proof of third-party authenticity; obtain the zip from the intended GitHub Actions run.

Do **not** ask the operator to stage/apply on the live PC merely because synthetic CI passed. Confirm that Java and Bedrock players can join and maintain an operator-attended maintenance window first.

## Stop condition and next optional work

There is deliberately **no new live Apply, Stop, Restart, or automatic Rollback entrypoint** in this kit. Before any future hotfix installation, a Canary→Canary **separate** service-only deployment/rollback design must safely retain the old Canary executable and registry service-only opt-in, preserve journals, prove the exact new binary in the running Host process, attest no proxy-owner markers, and recover the prior active Canary on failure. Host startup has indirect agent/autostart side effects; a green unit test is not real SCM E2E.

If this engineering cannot be proven without risking the operational Minecraft world, shelve direct Velocity management and keep the original scheduler mode. No work is lost: the isolated Canary code, tests, diagnostics, protected snapshots and rollback procedures remain in Draft PR #57.

**Do not share raw API tokens, private journals, service command lines or server.json.**
