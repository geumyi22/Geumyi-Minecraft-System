# Day 12.10 — GSC 4.3.9-rc.1 preview and separately approved production update gates

**2026-10-10:** Real server-PC guard precheck **4/4 compatible, 0 errors**. **Not deployed.** Strict `backend_ports_private` **FAIL**, Stable promotion blocked.

## Grounded input

Operator-supplied `Day12-GSC-Guard-Precheck-20261010-051837.json` at **05:18:37 +09:00** reports:

| Profile | Expected Java | Expected RCON | Config-guard compatible |
|---|---:|---:|---|
| wild | 25570 | 25575 | true |
| playground | 25571 | 25576 | true |
| other | 25572 | 25577 | true |
| lobby | 25573 | 25579 | true |

`result=CONFIG_COMPATIBLE_REVIEW_ONLY`, `issue_count=0`, `error_category=NONE`, all four `issue_codes=[]`, `read_only=true`, `synthetic=false`, no config/service/policy mutations. This **does not authenticate live RCON listener bind/ownership** and is not a 12.10 gate PASS. Original JSON remains outside the repository.

## RC pipeline failure discovered and corrected in source (not deployed)

- First isolated RC preview pipeline [run 37986580332](https://github.com/geumyi22/Geumyi-Minecraft-System/actions/runs/37986580332) **FAILED** at `go test ./...` because `compareGSCVersions` stripped prerelease suffixes. Therefore the temporary `appVersion=4.3.9-rc.1` was mistakenly considered equal to final `4.3.9`, and existing `TestDay11GSCVersionComparisonBlocksDowngrade` correctly refused it. No unsigned binaries were published as ready.
- Corrected `GSC/ServerCenter/cmd/host/self_update.go` to order prerelease below final release with distinct numeric prerelease identifiers; preserve build-metadata equality and unchanged stable/core number comparisons. Added regression tests for `4.3.9-rc.1 < 4.3.9`, `rc.2 < rc.10`, release > rc, malformed prerelease segments and leading-zero rejection.
- Re-triggered the preview job in `.github/workflows/day12-gsc-guard-rc-preview.yml` to use the corrected source; the next result is **PENDING** and must be confirmed before any artifact is called CI-pass. The source change is not a deployed GSC update.
- This is a real release-engineering bug revealed by the separate versioned preview attempt, **not evidence the live GSC 4.3.8 server is compromised or unsafe**. Existing strict `backend_ports_private` remains **FAIL**.

## Candidate packaging and safety model

- **Current deployed + source baseline:** GSC Host/Client/Setup **4.3.8**. Do not overwrite its version identity with a modified same-version binary; GitHub main stays 4.3.8.
- **Isolated GitHub CI:** `tools/day12/Build_Day12_GSC_Guard_RC_CI.ps1`, guarded by GitHub repo/run environment, builds a disposable *copy* of the source stamped **4.3.9-rc.1**. Source stamps include Host, Client, Setup, versioned README and snapshot naming; plugin release dependencies are acquired from the same workflow's validated System CI build.
- **Review-only artifact:** `GeumyiServerCenter-v4.3.9-rc.1-Setup.exe`, Host/Client binaries, `RC-METADATA.json`, `SHA256SUMS.txt` and `DO-NOT-INSTALL-README.txt`. **UNSIGNED**, no signed deployment manifest, not a Release, not ready for operators to run. Go unit tests and Host's non-destructive Day10 selftest are required in CI before artifact upload.
- **Rollback preparation:** keep a known-good **signed 4.3.8 installer/release** and hashes available; a source `git revert` is **not** a live service rollback. Only use tested installer/self-update transactional rollback after determining exactly what it changes, under explicit operator authorization. Do not copy/overwrite running Host EXE or protected configs manually.
- **Forbidden automation:** this preview must never call live update endpoints, push a signed deployment to Stable, alter OS firewall, change Java/RCON passwords or profiles, restart production Host/Paper/Velocity or touch the Golden backups.

## Completed isolated RC build evidence — 2026-10-10 (unsigned; NOT INSTALLED)

- **[GitHub Actions RC preview #37987306874](https://github.com/geumyi22/Geumyi-Minecraft-System/actions/runs/37987306874) — SUCCESS**, source `2e5bec5f4fa0275f6bef6266f7772de67e7a14b3`. The same workflow ran verified full baseline System CI, separately versioned Go Host/Client/Setup compilation in a disposable Windows source copy, `go test ./...` and GSC Host's non-destructive Day10 selftest.
- Verified actual CI artifact `gsc-4.3.9-rc.1-UNSIGNED-DO-NOT-INSTALL` / artifact **11643911781**, rather than relying on the green workflow label. Six ZIP entries had successful CRC, including three executables, metadata, warning and checksums. The five internal SHA-256 entries were recomputed from the ZIP members with **5/5 match**. Outer artifact SHA-256: `c9f6fc50837720efab826280b104a36d2b6f6fe48ffbf431baf2680ee133ded9` (CI review artifact identity only; not a signed release).
- `RC-METADATA.json`: `candidate_version=4.3.9-rc.1`, `deployed_baseline_version=4.3.8`, `review_only=true`, `unsigned=true`, `go_test_pass=true`, `day10_host_selftest_pass=true`, `operator_install_approved=false`, `production_host_modified=false`, `stable_published=false`, `backend_ports_private=UNCHANGED_FAIL`.
- **Regression fixed:** earlier failed RC CI runs `37986580332` and `37987139836` surfaced prerelease ordering/validation flaws in `compareGSCVersions`. Commit `2e5bec5f4` ensures `4.3.9-rc.1 < 4.3.9`, `rc.2 < rc.10`, malformed tags rejected before core comparisons, preventing prerelease clients from falsely rejecting final Stable versions. Prior failing experiments remain recorded; only the final validated RC artifact is usable as a *review input*.
- **Critical:** GitHub CI signing key was NOT invoked, no signed manifest was generated or uploaded, no canary/beta tag or Stable release published. Existing 4.3.8 installation/players/Worlds/Golden/RCON/firewall were not modified. **Do not give this unsigned preview Setup.exe to the operator as an install instruction**.

## Canary staging follow-up — signed-manifest GitHub Draft confirmed (2026-10-10)

- [Read-only Canary draft artifact audit `37988929955`](https://github.com/geumyi22/Geumyi-Minecraft-System/actions/runs/37988929955) **SUCCESS**: all 6 attached assets downloaded again; hashes and manifest Ed25519 signature cryptographically verified. Prior published 4.3.8 beta `deployment-public.pem` matched new signing key. Initial draft-create workflow `37988376060` errored after creating a valid Draft due GitHub GET-by-tag returning 404 for an untagged draft; it did NOT publish a visible release. Subsequent audit used authenticated releases-list API.
- Full evidence and exact deferred gates: `DAY12-PHASE10-GSC-4.3.9-RC1-SIGNED-CANARY-DRAFT-REPORT.md`.
- **No operator action yet:** this is a **GitHub DRAFT**, not a publicly discoverable Canary release; the original 4.3.8 install remains untouched. Separate tested publishing/tag pin plus controlled second-PC installation/rollback is required before any real-world E2E or server PC action. Signed *manifest* does not imply Windows PE Authenticode signing. Keep strict `backend_ports_private` FAIL.

## Preflight checklist — BEFORE asking the operator to install

1. Review the 4/4 latest on-host profile consistency against the candidate guard **at execution time**. The 05:18 report is current only as of capture; rerun it solely if configuration has since changed.
2. Confirm no active players, no in-progress GSC/GSCM pairing or update jobs, and an approved maintenance window. A GSC-only Host service restart can briefly interrupt control/console/monitoring even if Paper world processes remain running; do not claim downtime-free behavior.
3. Preserve **Golden protected checkpoints 4/4** and verify recoverability/integrity without taking a new backup or deleting one gratuitously. Ensure adequate disk, correct file permissions and validated 4.3.8 rollback installer before modification.
4. Verify production GSC Host/Client/update target versions, installation paths, managed-service persistence, self-update signing keys and genuine release-manifest provenance. Candidate **unsigned preview** fails signing/deployment criteria and must **not** be installed.
5. Confirm the rollback transaction affects only GSC binaries/Host service, not `server.properties`, world folders, Paper/Velocity, RCON credentials, firewall or other installed plugin components. Otherwise redesign rollout and ask for renewed consent.
6. Stage a signed prerelease (not Stable), review exact installed asset SHA-256, signature and manifest pin, and verify the rollback path on a disposable Windows machine with a known-good server control API session.

## Operator action gate — currently NOT READY

Only after the signed prerelease, preflight and rollback tests pass, explain to the user in Korean:
- the **exact** GSC-only version and installer/verified self-update action;
- which processes/services may restart and expected user-visible interruption;
- the exact rollback path to validated 4.3.8 and what evidence will be captured;
- expected Paper/Velocity/Geyser/GSCM impact and stop conditions;
- request **explicit permission** before any real service update.

Do not ask the operator to execute unsigned RC binaries. Do not treat the previous user permission to autonomously do GitHub/code/CI work as live-update authorization.

## After separately authorized real update

1. Verify GSC Host and Client actually advertise the candidate version and paired APIs remain authenticated.
2. Read-only check all 4/4 server profiles again and verify GSC preflight exposes `private_java_bind_config` status `ok` for intended private profiles.
3. Confirm GSC/RCON/console, Java clients via public Lobby, Bedrock clients via public ingress and last-safe-position transfer (selected representative E2E), Golden intact. An offline Other server is not a failure of a *configuration* check but cannot be claimed to be runtime healthy.
4. Roll back promptly on unexpected service process loss, traffic regression, update verification failure or version mismatch; collect sanitized outcome.
5. Independent **OS-current IPv4+IPv6 TCP listener+owner** proof is still required for strict `backend_ports_private`. **A new startup guard does not prove OS binding**, and successful Host deployment does not unblock final 12.11 E2E, 12.12 real soak, or 12.13 Stable unless their real gates pass.

## Stop and preserve state

If signing, release source integrity, rollback readiness or runtime safety cannot be demonstrated, **do not install**. Keep running 4.3.8, existing Windows policy and protected backups unchanged. Record the precise blocker rather than looping over more equivalent firewall/TCP/WFP diagnostics.

References: [source hardening](DAY12-PHASE10-SOURCE-SAFETY-FIX-20261010.md), [guard-compatible real host report handoff](DAY12-PHASE10-GSC-GUARD-ROLLOUT-HANDOFF.md), [current security decisions](DAY12-PHASE10-SECURITY-DECISION-PACKET.md).
