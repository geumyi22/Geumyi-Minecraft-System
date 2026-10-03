# Changelog

## 2026-10-04 — Canonical Day timeline / roadmap cleanup

- Added `DAY-TIMELINE.md` as the single source of truth for Day numbering and completion state.
- Clarified Day 4 as a real verification/closure milestone with no new implementation; later Day numbers are not shifted.
- Canonically marked Day 8 and Day 9 as **completed**. Their E2E PASS results are completion evidence, not partial-state labels.
- Kept Day 10 Java four-server/Lobby/routing/reboot verification complete while leaving the real Bedrock client E2E pending.
- Changed the current Day-10 closure rule from a permanent "wait for upstream" condition to **actual Bedrock client E2E required**; the original `SKIPPED_UPSTREAM_UNSUPPORTED` value remains historical evidence.
- Fixed roadmap drift across README, ROADMAP, VERSION-MATRIX, Day-10 plan/report, Network docs and deployment architecture.
- Fixed the Day 11 target scope to **GSC 4.3 / GSCM 1.1.5**: Update Center/fleet UX, startup update checks, managed Geyser/Floodgate/Via policy, player-aware restart/update and RCON/intentional-stop state fixes.
- Fixed Day 12 as Extended Automation & Production Hardening: Resource/DataPack deployment, StatusAgent/extended self-update, SBOM/provenance/security scans, reproducibility, shared cache, offline hardening and DR drill.
- Documentation-only cleanup; no runtime component is claimed updated or re-verified by this entry.

## 2026-10-03 — Day 10 four-server Java cutover

- Deployed three isolated Velocity proxy instances for Wild, Playground and Other public aliases, all routing first to Lobby.
- Moved Paper backends to private Java ports `25570/25571/25572/25573` and kept public Java on `25565/25566/25567`.
- Added/verified GeumyiNetwork and GeumyiLobby routing, physical Lobby gates, `/lobby`, and per-server last-position restoration.
- Hardened live cutover rollback for interrupted recovery, UTF-8 config safety, RCON fallback and exact proxy-process cleanup.
- Verified after a real Windows reboot that all three Velocity startup tasks are Running, public Java ports are LISTEN, and Geyser UDP ports `19132/19133/19134` are BOUND.
- User-confirmed Java E2E PASS: public join -> Lobby, Lobby -> Wild/Playground/Other, `/lobby`, and last-location restore.
- Bedrock client E2E is recorded as `SKIPPED_UPSTREAM_UNSUPPORTED` because the current latest Geyser does not yet support the current Bedrock client version. Bedrock client verification remains pending; this is not recorded as a Bedrock PASS.
- Exact validation baseline for the final recovery-safe cutover source: `0e1490bfe75975eb278526df0f89a430109e28d8`; Day10 Hotfix CI `37113499045` and System CI `37113499031` both succeeded.

## 2026-09-29 — Day 8 secure release / updater foundation

- Added signed Day-8 Secure Release workflow with Stable/Beta/Canary channels, SHA-256 verification and Ed25519 deployment manifests.
- Added persistent Android release-signing path and GSC pre-start updater with fail-open behavior.
- Added GSC Update Center first-stage UI/API and one-run local/server E2E finalizer.
- Bumped GeumyiTechnology to **0.1.4** as a metadata-only Wild updater E2E marker; gameplay logic remains the recovered/verified 0.1.3 baseline.
- Added/updated Day-8 operator documentation.
- Published and verified signed canary Release `system-2026.09.29-222513-canary` via Secure Release run `36574955584`.
- Completed the server-PC Day-8 finalizer with user-confirmed `DAY 8 RESUME FINALIZER: PASS`: Wild Technology 0.1.4 applied/current and Playground isolation verified.
- Hardened the Windows finalizer during live E2E: ASCII/no-BOM CMD launcher, correct post-login auth verification, JDK keytool discovery, always-visible failure logs, and installer-process-only waiting with safe Release resume.
- **Day 8 closed.** Transaction journal, post-start health gate, automatic rollback and failure injection move to Day 9.

## 2026-09-27 — Recovery completion and Day-4 verification

- Completed GST 1.1.1 HOTFIX, StatusAgent 0.5.4, GeumyiTechnology 0.1.3 and GeumyiChemistry 0.4.1 source recovery/reconstruction tracking.
- Captured sanitized live Wild/Playground server configuration evidence and completed Day-4 E2E verification.
- Kept runtime binaries in GitHub Releases rather than the source tree.
- Removed the unused `release-source.example.txt`; the release workflow uses the explicit `source_url` input plus `release-tag.txt` / `release-sha256.txt`.

## 2026-09-26 — Source recovery

- Expanded GSC 4.2.3, partial Agent 0.5.4, GSCM 1.1.2+112 and GDS 1.1.1 into their component directories.
- Expanded current Wild/Playground Java and Bedrock resource packs with original asset bytes.
- Replaced GSCM base64 archive with the real source tree; retained existing build steps and Android compatibility settings. Corrected iOS artifact label to 1.1.2.
- Recorded missing exact GST HOTFIX, Technology, Chemistry, Agent helper and server configuration sources explicitly.
- Excluded bundled executables/JARs/APKs/IPAs, old source/docs, missing-script launchers, runtime state and packaging duplicates.
- Replaced the private-looking QR-test address with a synthetic example; retained blank/placeholder-only configuration templates.
- Left existing release assets unchanged.
