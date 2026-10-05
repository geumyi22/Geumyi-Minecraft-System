# Day 11 — Operations UX & Fleet Management

Status: **IN PROGRESS — Phase 11.0 live preflight PASS; latest Day 11 repo-side GSC/GSCM CI PASS; live host/device E2E still required before closure**
Target: **GSC 4.3.0 / GSCM 1.1.5**

## Safety rules

1. Host preflight is read-only except for writing a report under the selected output directory.
2. Do not force-kill Paper backends. Graceful lifecycle APIs/RCON are the only normal shutdown path.
3. Before any live replacement: preflight -> backup -> checksum/signature -> change -> health -> rollback on failure.
4. Never expose RCON passwords, device tokens, Floodgate keys, or signing private keys in reports.
5. A CI/static PASS is not a live E2E PASS.
6. A new build/version alone is not proof of runtime compatibility.
7. Pending update/rollback assets may not be deleted while referenced by an active transaction.

## Phase 11.0 — Read-only baseline

- main/branch SHA and component versions
- GSC host health
- Wild/Playground/Other/Lobby profiles and private ports
- public Java 25565/25566/25567
- public Bedrock UDP 19132/19133/19134
- Velocity/Geyser/Floodgate/Via artifacts
- scheduled startup tasks
- update transaction residue
- backups/checkpoints and disk free space
- no process stop, firewall edit, server config edit, or world write

Tool: `tools/day11/Day11_Phase0_READ_ONLY.cmd`

## Phase 11.0 result

The user executed the read-only host preflight on 2026-10-04. See `DAY11-PHASE0-REPORT.md`.

Key follow-ups:
- Other backend was offline with `auto_start=false` and live `accepts-transfers=false`; record as drift and do not silently change host policy.
- Other still had Technology 0.1.3 while the managed baseline is 0.1.4.
- backup footprint was ~198.6 GiB, so Protection & Recovery 2.0 is prioritized.
- no pending update artifact was detected.

## Phase 11.1 — Operations correctness

- RCON false `관리 제한` suppression using passive listener + recent authenticated RCON success
- exact console `stop` semantics: intentional stop -> desired_running=false; send failure restores prior desired state
- normal intentional shutdown -> OFFLINE; actual unexpected loss with desired=true -> RECOVERING
- Day-10 topology-aware Bedrock status using public Velocity/Geyser entrypoints, not backend `bedrock_port=0`
- GSC PC registered-device UI exposes **revoke / restore / delete** distinctly
- device delete permanently removes the registration record; re-pair is required

## Phase 11.1 host-test deployment

Before merging broader Day 11 Update Center work into the live host, a GSC-only host-test package is built.

Safety boundary:
- backs up only installed GSC binaries + `server.json`;
- closes/requires the desktop GSC client to be closed before replacement;
- stops **only** the Windows service `Geumyi Server Center Host`;
- does not stop Paper/Minecraft or Velocity;
- verifies every TCP/UDP entrypoint that was open before remains open;
- verifies package SHA-256 and installed binary SHA-256;
- waits for GSC `/api/health`;
- automatically restores previous GSC binaries if the new Host fails health or network-preservation checks;
- includes a separate manual GSC-only rollback launcher.

Artifact target: `day11-phase1-gsc-host-test`.

Live runtime PASS is not claimed until the user runs this package on the server PC.

## Phase 11.2 — Update Center 2.0

- installed/latest verified version
- Stable/Beta/Canary
- managed/manual/hold/pin
- dry-run
- next-start / next-restart / maintenance window
- history, validation, rollback result
- GSCM remote controls

## Phase 11.3 — External proxy component management

- Geyser/Floodgate/ViaVersion/ViaBackwards official metadata
- staging + verification
- preserve configs and Floodgate identity
- player-aware restart
- Java + RakNet readiness
- rollback
- Paper remains separate notify/manual-approve by default

## Phase 11.4 — GSC self-update

- startup latest-verified-build check
- helper-based replacement
- signature/hash verification
- relaunch health gate
- rollback
- network/update lookup failures are fail-open

## Phase 11.5 — GSCM 1.1.5 distribution

- Android in-place update with persistent signer
- iOS update discovery respecting signing/provisioning constraints
- no false claim of silent IPA installation

## Phase 11.6 — Full fleet UX

- Update Center UI renewal
- per-server policy and fleet state
- player-aware scheduling
- canary promotion
- notifications/audit

## Phase 11.7 — Protection & Recovery 2.0

- backup metadata/source reason
- protect/pin
- delete -> trash/quarantine
- restore from trash
- permanent delete with confirmation
- deny deletion of active rollback/transaction references
- retention + disk guard + dry-run
- restore preflight/checkpoint/verify/health
- GSCM controls

## 2026-10-05 repo-side progress

Day 11 runtime-code baseline evidence: `ff5aa528e04c9d84f3ba788d764a3304b8444dd4` (the following documentation-only commits do not change runtime code).

Completed in source/CI without touching the live Minecraft/Velocity processes:

- Update Center fleet policy now supports per-server managed/manual/hold, Stable/Beta/Canary inheritance/override, signed release pinning and dry-run.
- GSC/GSCM expose the fleet policy controls without restarting a server merely by saving policy.
- Geyser/Floodgate/ViaVersion/ViaBackwards have official-metadata inventory plus SHA-256-gated **staging only**. Live proxy/backend JAR replacement is not claimed.
- GSC self-update has signed manifest discovery, fail-open startup checking and verified artifact staging. Live helper replacement/relaunch rollback is still a runtime gate.
- RCON authenticated health evidence is tied to the current server lifetime rather than a fixed 12-hour TTL.
- Protection & Recovery adds backup source-size disk preflight, protected/checkpoint retention exemptions, retention **dry-run**, and a conservative delete guard while a pending update transaction exists.
- GSC and GSCM expose backup retention preview; preview never deletes files.
- GSCM target is `1.1.5+115`; Android release APK and unsigned iOS IPA CI builds both passed.

CI evidence:

- System CI run `37317107084`: **PASS** on the current main SHA.
- Day 11 Host Test Package run `37317107060`: **PASS** including `go test ./...`, WindowsGUI Host/Client build, script parser and safety guard.
- Host-test artifact `11349015100`, digest `sha256:c0193ba301bd7d3aa678e732b034f9a41ea1a10a1a29ad2ea17e3cd3bd60381a`.
- GSCM Android run `37316499921`: **PASS**, artifact `GSCM-1.1.5-build115-Android`.
- GSCM iOS run `37316499905`: **PASS**, artifact `GSCM-1.1.5-build115-iOS-unsigned`.
- GSCM control tests run `37316500013`: **PASS**.

These are CI/build results only. They do **not** convert the remaining live host, Android/iOS device, Java, Bedrock, external-component apply/rollback or final E2E gates to PASS.

## Completion boundary

Day 11 is complete only after:
- GSC and GSCM CI passes;
- synthetic failure/rollback tests pass;
- server-PC host E2E passes;
- Android/iOS flows are checked on real devices as applicable;
- Java and Bedrock routing remain healthy after the update work;
- no unverified item is labeled PASS.
