# Geumyi Server Center 5.0.0-beta.1 — Single Beta

**Prerelease only. Not Stable.** This is the **one and only beta candidate** requested before the operator's eventual manual Stable 5.0.0 release.

## What's included

GSC Host, Desktop Client and Windows Setup all carry exactly `5.0.0-beta.1` and are newly built from the audited GSC 4.5.1 stable source baseline. The current Host/Client separation, monitoring, player-aware server jobs, backups and protected restore preflight, external plugin updates, self-update paths and GSCM-compatible **v4** APIs are retained. The new authenticated `GET /api/v5/release` exposes read-only product version/channel and safety capabilities; it does not change server lifecycle behavior.

- Windows installer: `GeumyiServerCenter-v5.0.0-beta.1-Setup.exe`
- Host: `GeumyiServerHost.exe`
- Client: `GeumyiServerCenter.exe`
- SHA-256 digests: `SHA256SUMS.txt` (verify before installing)
- Provenance: `SOURCE-COMMIT.txt` (exact source commit), `RELEASE-CHANNEL.txt`

**GSCM remains v1.5.1+151.** Android/iOS binaries are not modified, rebranded, or implied to have passed 5.0.0 live tests.

## Deliberately excluded

The abandoned GSC-owned Velocity direct start/stop/restart project from Draft PR #57 and companion experimental branches **is not merged**. The 3 existing original Windows Scheduler Velocity tasks remain the sole proxy lifecycle owners. No beta functionality disables or adopts them.

## Deployment/compatibility and risks

- **Do not install directly on the operational server from GitHub CI alone.** Prepare a tested original Host/Client executable and config backup, service rollback, check Minecraft player activity, and schedule operator-attended maintenance.
- This is a Windows x64 prerelease based on the previous 4.5.1 source; no production Host/Client/Android/iOS Java/Bedrock E2E for 5.0.0 has been observed. A successful CI build is not live QA.
- Active GSC 4.5.2 Canary Host + service-specific opt-in configuration is an **exceptional previous test environment**. Existing first-time 4.5.1→Canary swap kits are NOT safe as an upgrade path. Do not run them.
- No new `deployment-beta.json` or `deployment-stable.json`, no signed auto-update manifest and no automatic installation are shipped by this GitHub prerelease. The older signed Beta channel remains separate. An unsigned release ZIP/asset must never be mistaken for an approved signed automatic-update candidate.
- The existing final release gate remains blocked: `FINAL-RELEASE-GATES.json` sets `stable_release_allowed=false`; kernel port ownership, live security/soak and other required gates remain unresolved.
- Use staged/offline testing first and preserve protected worlds, configuration, backups and rollback journal. Do not share API/RCON/device tokens, signed deployment private keys, log secrets, or private journals.

## Beta checks and definition of ready

CI must show Windows Go tests, compiled **Host + Client + Setup**, Host selftest, checksum verification, legacy component build tests, release-foundation checks, security/SBOM and read-only safety workflow results. Only then can the beta prerelease be published, always as `gsc-v5.0.0-beta.1` with `prerelease=true` and `latest=false`. Publication is idempotent **fail-closed**: an existing tag/release is never moved or overwritten.

## Stable is operator-owned

**No bot/CI promotes beta to Stable automatically.** Stable 5.0.0 tagging, signing, package promotion and GitHub Latest selection are reserved for the operator after a separate live QA decision and the required Stable checks. This document does not instruct or authorize bypassing the existing Stable release gates.
