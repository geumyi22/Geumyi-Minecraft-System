# GSC 5.0.0-beta.1 — operator QA and release-readiness runbook
**2026-10-26 · draft procedure only; no production action is authorized by this document.**

## Known baseline (different kinds of evidence)
- Official immutable GitHub prerelease: `gsc-v5.0.0-beta.1`; target commit `3283f769c96eeb5f4ffe9c2ebfbfa7d028a6d4b6`. Source/Host/Client/Setup report `5.0.0-beta.1`.
- GitHub CI/packaging succeeded; this is **not** a live install, Java/Bedrock smoke, device E2E, or full soak pass.
- Prior operator-reported GSC Host 4.5.2 Canary installation is an **exceptional installation**, not the normal 4.5.1 stable baseline. Its old swap/rollback scripts must not be reused for beta upgrade.
- GSCM remains `1.5.1+151` and continues to use v4 APIs; do not update/rebrand mobile artifacts.
- All three Velocity proxy lifecycles remain owned by the original Windows Task Scheduler jobs. Never migrate, disable, stop, or duplicate them for this beta.
- `FINAL-RELEASE-GATES.json` retains `stable_release_allowed=false` and a failing canonical native backend listener-ownership/privacy gate. Do not auto-publish or auto-install Stable 5.0.0.

## Phase A: offline artifacts — no server contact
1. On a **separate test PC**, download the **seven** assets from the one official beta release. Do not mix binaries from older releases or branches. Inspect `SOURCE-COMMIT.txt` and `RELEASE-CHANNEL.txt`.
2. In the repository checkout of this hardening PR, run this strictly read-only **local** verification against the downloaded asset directory:
   ```powershell
   powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\tools\gsc5\Test-GSC5BetaOfflineAssets.ps1 -AssetDirectory "C:\GSC5-Beta-Downloads"
   ```
   Success marker: `GSC5_BETA_OFFLINE_ASSETS_PASS`. The script only reads local files, checks SHA-256/commit/channel flags, and rejects unexpected/missing EXEs. It never executes an installer.
3. Record the asset filenames, SHA-256 values, source commit and the actual current local app versions. Do **not** copy pairing tokens, RCON secrets, private keys or private recovery receipts into public CI logs.

## Phase B: non-production installation and compatibility
1. Use an isolated Windows x64 test environment with **disposable** data, not a copy that can reach or mutate live server worlds. Preserve the test system snapshot and clean rollback point.
2. Test a fresh installer separately from a 4.5.1 stable upgrade. Test Host-only, Client-only, and combined-role installation paths only with disposable config.
3. If the production server reports Host 4.5.2 Canary, treat it as a **third migration path**. This beta is derived from stable 4.5.1, not the Canary experimental features. Migration from a Canary service must be designed and approved separately, with service SHA, ACL, rollback and config behavior verified first. Do not run the old Canary swap kit.
4. Confirm the Host is a Windows service only when intentionally configured, Client remains independent, version identities match, and uninstall/reinstall/rollback restores the previous tested binaries and settings. Never infer a successful rollback from file presence alone.
5. Check `GET /api/v5/release`: 200 JSON + no-store on valid authorized requests; unauthenticated remote private/tailnet callers get 401; disabled remote mobile access gets 403; unsupported methods return 405 after authentication. Legacy v4/GSCM endpoints must continue to work.
6. Confirm GSC Host, Client and GSCM coexist without triggering a signed automatic Stable promotion or changing the three original Velocity job definitions.

## Phase C: operator-attended live read-only baseline (before scheduling changes)
- Confirm exact running Host/Client/GSCM version and hashes; compare installed executable source with expected package. Do not assume the local 4.5.2 Canary service will upgrade cleanly.
- Read existing Windows service/task configuration and backup metadata; avoid force-killing Java, changing task state, opening new public ports, or overwriting task XML.
- Verify separately: authenticated Host status, Paper/Geyser/Floodgate/Velocity inventory, RCON readiness, Java and Bedrock gameplay entry/routing, GSCM Android/iOS paired-device status, backup/restore *preflight only*, and client self-update dry-run.
- Reconcile canonical backend TCP/RCON native listener **owner and bind address**. LAN/Tailscale remote negative connects alone do not prove the actual kernel listener owner. Do not change the canonical failing release gate without new independently reviewed evidence.
- Arrange an explicit maintenance window **only after** backup, rollback, security review, and expected impact on online players are understood. No unattended installation.

## Phase D: separate authorized live QA — still not automatic Stable
Each row needs timestamp, device/OS/app version, expected vs. observed behavior and evidence classification:

| Check | Required evidence |
| --- | --- |
| Windows Host+Client service upgrade | Old and new binary SHA, service stop/start ownership, config preservation, rollback demonstrated |
| Server state | Wild/Playground/Lobby and intentionally-off Other distinguished; no accidental start |
| Java client | Public entry, Lobby, selected target, return, last location, reconnect |
| Bedrock client | Geyser/Floodgate entry and travel, version compatibility and reconnect |
| GSCM Android and iOS | Remote status/auth/session, lost-network recovery, approved read-only and authorized control regression |
| Protection & Recovery 2.0 | Golden archive presence/checksum, retention protection, dry-run/restore preflight; live world restore only in separate disposable copy |
| Stability/soak | Defined duration, failures, CPU/RAM handles, alerts and player effect, backup and recovery evidence |
| Security | Private native bind ownership, firewall/ACL effective rights, secrets handling, update signing / provenance |

**Stop/rollback triggers:** mismatched SHA or source, duplicate Velocity owners, changed task XML, unexpected Paper start/stop, inability to restore previous Host, failed auth boundary, exposed private port or changed original backup. Do not force-kill all Java processes.

## Release decision
- CI PASS + GitHub prerelease published: **confirmed**.
- Offline artifact readback: **pending operator execution**.
- Isolated Windows Host/Client/Setup verification: **pending**.
- 5.0.0 real Java/Bedrock/GSCM live E2E + soak: **pending**.
- Canonical native backend bind/owner and formal Stable gates: **blocked**.
- Promotion of 5.0.0 Stable, signed manifests and GitHub Latest: **operator-only** after all mandatory gates independently pass. Never change the existing published beta release or tag.

Reference: [integration ledger](GSC-5.0.0-BETA-INTEGRATION-2026-10-25.md), [release notes](../releases/GSC-5.0.0-beta.1.md), [formal gates](../../FINAL-RELEASE-GATES.json).
