# Day 11 — Operations UX & Fleet Management

Status: **IN PROGRESS — Phase 11.0~11.6 complete; Phase 11.7 and Day 11 Final E2E remain**
Current live verified target: **GSC 4.3.7 / GSCM 1.1.5+116**
Current source/CI candidate: **GSC 4.3.8 / GSCM 1.1.5+117** (Protection & Recovery 2.0; live validation pending)

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

## Phase 11.1 — Operations correctness — ✅ LIVE PASS

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

## Phase 11.2 — Update Center 2.0 — ✅ LIVE PASS

- installed/latest verified version
- Stable/Beta/Canary
- managed/manual/hold/pin
- dry-run
- next-start / next-restart / maintenance window
- history, validation, rollback result
- GSCM remote controls

## Phase 11.3 — External proxy component management — ✅ LIVE PASS

- Geyser/Floodgate/ViaVersion/ViaBackwards official metadata
- staging + verification
- preserve configs and Floodgate identity
- player-aware restart
- Java + RakNet readiness
- rollback
- Paper remains separate notify/manual-approve by default

## Phase 11.4 — GSC self-update — ✅ LIVE PASS

- startup latest-verified-build check
- helper-based replacement
- signature/hash verification
- relaunch health gate
- rollback
- network/update lookup failures are fail-open

## Phase 11.5 — GSCM 1.1.5 distribution — ✅ USER DEVICE PASS

- Android in-place update with persistent signer
- iOS update discovery respecting signing/provisioning constraints
- no false claim of silent IPA installation

## Phase 11.6 — Full fleet UX — ✅ LIVE PASS

- Update Center UI renewal
- per-server policy and fleet state
- player-aware scheduling
- canary promotion
- notifications/audit
- signed Canary rollout verified live in order: Playground -> Wild -> Other -> Lobby
- offline Other correctly blocked the next promotion (fail-closed health gate)
- Other was backed up and verified before start; Technology 0.1.4 applied and post-start health passed
- rollout completed with `active=false`, `completed=true`, and `server_restart_performed=false`
- all server update policies were restored to `managed + inherit` with empty pins and global `beta`

## Phase 11.7 — Protection & Recovery 2.0 — 🔄 SOURCE/CI IN PROGRESS

Implemented in the 4.3.8 / GSCM build117 candidate:
- backup metadata/source reason (`manual-dashboard`, `manual-gscm`, `automation:<id>`, restore checkpoint reason)
- protect/pin metadata
- delete -> trash/quarantine and restore from trash
- permanent delete requires both a server-side confirmation token and exact filename confirmation
- deletion/retention remains blocked while an update transaction is pending
- scheduled backup pruning now moves **only automation-owned** backups to Trash; it no longer directly deletes files or prunes manual backups
- retention dry-run + confirmed all-or-nothing Trash apply + disk guard
- restore preflight verifies offline state, server identity, backup SHA/ZIP and checkpoint disk capacity before mutation
- restore creates a protected checkpoint, verifies offline post-restore roots, and automatically rolls non-full restore failures back from the checkpoint
- GSC dashboard and GSCM expose provenance, restore preflight and destructive-action safeguards
- `tools/day11/Day11_Phase7_Protection_READ_ONLY.cmd` provides a no-mutation live verifier

Candidate/release evidence:
- GSC 4.3.8 System CI `37617403835`: PASS; `gsc-4.3.8-ci` artifact id `11479763609`, digest `sha256:cab175afdd9a9b07e0d199dee9ff5ddf4383c216062ed8f2b12a7a528cb235cb`.
- GSCM build117 Android `37617292391` / iOS `37617292404` / controls `37617292420`: PASS.
- Secure beta release `system-2026.10.07-day11-gsc438-beta` workflow run `37627140918`: PASS, published from `a17975030ed3f9b71d8632a7897c1c206d9bfcdf`.

Still required before LIVE PASS:
- server-PC 4.3.7 -> 4.3.8 update
- Phase 7 read-only live report and safe disposable backup lifecycle checks

## 2026-10-07 live/source progress

- Phase 11.6 Full Fleet UX: **LIVE PASS** on GSC 4.3.6.
- Canary release `system-2026.10.07-day11-116-canary.1` was promoted Playground -> Wild -> Other -> Lobby with health gating.
- Offline Other correctly blocked Lobby promotion until Other was intentionally started; no automatic server start/restart was performed by Canary promotion.
- Other full backup was created and SHA-256 verified before start. Its managed update applied GeumyiTechnology 0.1.4 and post-start health verification passed.
- Canary rollout then completed and the four server policies were restored to `managed / inherit / no pin`; global channel is `beta`.
- A remote-management UX defect was then found: a remote Windows GSC Client showed the server PC Host self-update state as if it were the local Client update state.
- GSC 4.3.7 source/CI separates **this PC GSC Client** update from **server PC GSC Host** update. Local Client staging uses the signed release metadata supplied by the trusted Host, downloads the Setup artifact on the local PC, verifies size + SHA-256, and runs a client-only helper that does not stop or replace the remote Host.
- GSC 4.3.7 source/CI evidence: System CI run `37583159508` PASS; artifact `gsc-4.3.7-ci` id `11465376458`, digest `sha256:ecdd1b20cc2166fde1b627d7a5630935793d92d68d8590afb1df47696cc36b33`. Day 11 Host Test Package run `37583159609` PASS; artifact id `11465776442`, digest `sha256:60b70a732da3ac20ac420fee79d16ae7f4aeb1dffc59f6f1638c2569f2bcb335`.
- Secure beta Release `system-2026.10.07-day11-gsc437-beta` was published successfully. The server PC and remote management PC were both installed on 4.3.7, and the remote UI showed the local Client and connected Host as separate 4.3.7 current-version cards. The **Client/Host update-state split and local version detection are LIVE PASS**.
- The **in-app local Client version replacement path is now LIVE PASS**: the remote management PC staged the signed 4.3.8 release from local Client 4.3.7, then applied the Client-only updater and came back on 4.3.8 while the server PC Host remained on 4.3.7.
- Phase 11.7 source work then started on GSC 4.3.8 / GSCM 1.1.5+117; no 11.7 LIVE PASS is claimed yet.

## 2026-10-06 live progress

- Phase 11.1 / 11.2 / 11.3: user confirmed remaining live checks complete; record as **LIVE PASS**.
- GSC self-update: **4.3.1 → 4.3.2 LIVE PASS**. Helper report returned `status=success`, `rolled_back=false`, `host_health=true`, `client_relaunched=true`, Session 1 relaunch.
- Wild RCON status after update: `online=true`, `java_port_open=true`, `rcon_port_open=true`, `gds_api_online=true`.
- GSCM hard-coded `1.1.2` display was replaced with package metadata-based version display.
- GSCM build advanced to **1.1.5+116** so Android versionCode increases for in-place update.
- Secure beta Release `system-2026.10.06-day11-gscm116-beta` published successfully from commit `0e1c17c649cddb52829346311f013ed967f48b9a`.
- Persistent-signed Android APK and unsigned iOS IPA were published; user confirmed device installation/distribution flow.
- Day 11 is **not closed yet**: Phase 11.7 and Final E2E remain.

## 2026-10-05 repo-side progress

Day 11 runtime-code baseline evidence: `22c233ab32b3f3022c956d7dd8fc7b552d48d703`.

Completed in source/CI without touching the live Minecraft/Velocity processes:

- GSC source/package target is now **4.3.0** while the last promoted live baseline remains 4.2.4 until host E2E.
- Update Center fleet policy supports per-server managed/manual/hold, Stable/Beta/Canary inheritance/override, signed release pinning and dry-run.
- GSC/GSCM expose fleet policy controls without restarting a server merely by saving policy.
- Geyser/Floodgate/ViaVersion/ViaBackwards have official-metadata inventory plus SHA-256-gated **staging only**. Live proxy/backend JAR replacement is not claimed.
- GSC self-update now has signed manifest discovery, fail-open startup checking, verified artifact staging and a **headless helper replacement path**. The helper creates a GSC-only backup, closes/relaunches only the GSC desktop client when needed, stops only the GSC Host service, replaces GSC binaries, runs an HTTP health gate and restores the previous GSC binaries on failure. Minecraft/Paper/Velocity are not targeted by this helper. Live self-update execution is still a runtime gate.
- RCON authenticated health evidence is tied to the current server lifetime rather than a fixed 12-hour TTL.
- Protection & Recovery adds backup source-size disk preflight, protected/checkpoint retention exemptions, retention dry-run and active-transaction deletion guards.
- Retention **apply** is now source-implemented as an all-or-nothing move to GSC Trash, not permanent deletion. It requires an explicit confirmation token, rechecks pending-update protection and rolls already-moved candidates back if the batch fails.
- GSC and GSCM expose retention preview + confirmed retention apply.
- GSCM target is `1.1.5+115`; Android release APK and unsigned iOS IPA CI builds pass.

Latest CI/build evidence:

- System CI run `37323031612`: **PASS** on runtime SHA `22c233ab32b3f3022c956d7dd8fc7b552d48d703`, including **GSC 4.3.0 / Go test** and **GSC 4.3.0 / assemble CI Setup**.
- GSC 4.3.0 CI artifact `11350918253`, digest `sha256:37ec5fbb03b848ee2cfe2c7f53427ba6619af7ef9619e8504384d7a8ca69089b`.
- Day 11 Host Test Package run `37323031699`: **PASS**. Artifact `11350348741`, digest `sha256:34c099789a8da85a125e54fe0cfc16231ec4290a3623eb207be60e2c067e82bf`.
- GSCM Android run `37321966682`: **PASS**. Artifact `11349963322` (`GSCM-1.1.5-build115-Android`), digest `sha256:727b6abe091c735c1f46e51399c2a73d2b81f2df1e111d0942381c6bcb672d8e`.
- GSCM iOS run `37321965954`: **PASS**. Artifact `11350847140` (`GSCM-1.1.5-build115-iOS-unsigned`), digest `sha256:4c1a5b15c675f07a97b44ab1cfba3e88f6e8c37a159d398ef75bfac035ed6f34`.
- GSCM update/control tests run `37321966119`: **PASS**.
- Day 10 GSC Dashboard UI regression run `37321966080`: **PASS** after retention UI changes.

These are source/CI/build results only. They do **not** convert live host, self-update helper execution, Android/iOS device, Java, Bedrock, external-component apply/rollback or final E2E gates to PASS.

## Completion boundary

Day 11 is complete only after:
- GSC and GSCM CI passes;
- synthetic failure/rollback tests pass;
- server-PC host E2E passes;
- Android/iOS flows are checked on real devices as applicable;
- Java and Bedrock routing remain healthy after the update work;
- no unverified item is labeled PASS.
