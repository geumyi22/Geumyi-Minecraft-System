# GSC 5.0.0-beta.1 — unified prerelease plan and verification ledger

## Source of truth

- Base: GitHub `main` at `2f0b6c1d6138b24689df5532c0951004b1e0f221` (GSC 4.5.1, GSCM 1.5.1+151).
- Integration branch: `release/gsc-5.0.0-beta.1`, PR #60.
- No merge from experimental Velocity PR #55/#57/#58 or unreviewed stacked Day12 security PRs #47–#53.
- Naming: Host/Client/Setup/code/catalog `5.0.0-beta.1`, GitHub immutable beta tag `gsc-v5.0.0-beta.1`. **Stable 5.0.0 not created**.
- Existing APIs stay v4 compatible, new v5 release endpoint is informational only.

## Functional scope reused from tested existing GSC source

| Subsystem | Beta approach | Risk gate |
|---|---|---|
| Windows Host background service and split Client | Preserve existing source and role behavior; beta identity synchronized | Production service rollback needs operator-attended proof |
| Dashboard & remote GSCM APIs | Preserve v4 API for v1.5.1+151 GSCM | Manual Android/iOS live regression is not CI |
| Lifecycle, RCON, monitoring, TPS/MSPT, logs | Preserve current behavior, no speculative process ownership rewrite | Require actual Minecraft client smoke before Stable |
| Backup, Golden checkpoints, restore preflight and recovery | Preserve Protection & Recovery 2.0 and recovery journals | No destructive backup/restore tests on live worlds |
| Signed manifest engine, update channels, Host/Client self-update | Preserve update verification; **do not auto-release signed Stable or Beta manifests** | No live updater APPLY without independent approval |
| GDS/GST/StatusAgent, plugin/update inventory | CI-built existing component versions unchanged | Do not silently upgrade deployed plugin jars |
| Velocity/Geyser/Floodgate routing | Keep three original Scheduler owners | GSC direct lifecycle permanently out of this beta |
| GSCM Android/iOS | Keep 1.5.1+151 | Do not claim updated mobile device binaries |

## Regression and release gates

1. Compile and test all Go packages (Windows). Test application version monotonicity and `/api/v5/release` strict GET-only contract.
2. Assemble actual Host/Client/Setup payload using pinned CI-built GDS/GST/StatusAgent, verify file hashes and nontrivial EXE sizes, then run Host selftest.
3. Run System CI full component, network/resourcepack, update-release foundation tests and the Day12 security/SBOM and Day12 safety reusable workflows.
4. Publish **exactly one** GitHub prerelease only after all above PASS. Upload executable SHA-256 and exact source commit. Do not set Latest.
5. Save an operational distinction between **CI_PASS**, **PRERELEASE_PUBLISHED** and **LIVE_E2E_PASS**. None implies the next.
6. Operator chooses final Stable release later; retain `FINAL-RELEASE-GATES.json` stable gate until independently verified.

## Explicitly outstanding for production

- Latest operator report: existing Wild original Scheduler and Java+Bedrock related components were restored after an aborted Canary direct-ownership experiment; this is **not** evidence that GSC 5.0.0 is installed.
- 5.0.0-specific real Windows installer upgrade/rollback and long-lived GSC Host service smoke.
- Actual Java and Bedrock join/transfer test, Android and iOS client status/control verification, and formal soak.
- Canonical native backend TCP/RCON bind ownership privacy and release signing requirements.
- GSC Host API token rotation and paired client impact planning (previous token exposed in conversation).
- Stable signed deployment manifest/Latest release intentionally user-controlled.

## Operator guidance

**No production command is needed for source CI or publishing the beta.** Avoid old Canary swap scripts, Velocity cutover tooling, and risky restart. Once the beta exists, use a separate stage/test PC and compare original service/config backup before any real Host deployment. Keep GSCM and existing worlds unchanged.
