# Changelog

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
