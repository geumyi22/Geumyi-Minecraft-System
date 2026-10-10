# Day 12.7 — Offline known-good, independent Windows Sandbox design

## Why a second live GSC Host is prohibited

The real 2026-10-10 10:58 Playground precheck passed all except `AUTOMATIC_UPDATE_POLICY_MUST_BE_REVIEWED`: current updater policy is not demonstrably manual/hold. Do not change the production setting or rerun that unchanged precheck.

GitHub's **production** `GSC/ServerCenter/cmd/host/main.go` `runHostCore()` does more than bind a configurable API: it calls `initRuntimeState`, `initV4Runtime`, `initV41Runtime`, **`syncMobileFirewall`**, restores lifecycle schedules, and **`reconcileLocalCompanionConfigs`** at startup. A second Host run on the serverPC—even with `--config`—could impact the Windows network policy or companion config. **Never start a second Host directly on the production Windows OS** to simulate offline behavior. Go test-only launch/HTTP transport stubs and truly isolated VM execution are different.

## What is already established

- **84/84 real server-PC known-good cache file hashes+sizes verified**; no cache corruption.
- **Golden full protected 4/4**; current production config/world preserved.
- **Playground real preflight**: GSC 4.3.8 Running, 0 active jobs, 0 players, unique target, online, protected full backup present, no `block_start`, safe updater phase. Only update-policy safety guard blocks.
- **Disposable Go integration tests**: HTTP source failure, unchanged prior JAR, `BlockStart=false` in ordinary failure, `manual/hold` preserves old JAR; interrupted rollback that cannot be recovered is intentionally blocking. More recent `day12_github_offline_cache_test.go` validates reusable **30-minute-old public GitHub metadata after the local test HTTP server is disconnected**, and **rejects** metadata older than the 24-hour stale limit. These tests do **not** start Paper, are not the real operator's network, and are not an in-place signed deployment manifest validation.

## Stage design; no live-test execution yet

**Preferred, if Windows Sandbox is supported and explicitly enabled on the serverPC:**
- Use **Windows Sandbox configured with `<Networking>Disable</Networking>`**, no NAT bridge or real external listener. Windows Sandbox is a temporary separate guest OS, not a second process on the production host.
- Map **only** approved GSC Host binary, one expected Paper server JAR, one trusted **public** update verification key, a suitable Java runtime and temporary harness. **Never map** production `server.json`, worlds, backups, logs, GSC control token, Discord/GDS secrets, API secrets, custom pack private Dropbox links, GSCM pairing data, Tailscale profile or any other live program data into guest. Java runtime is read-only. Sandbox's fresh Paper world and all generated files are disposable.
- Guest GSC Host uses a newly generated **guest-only** `--config`: one target `stage-playground`, guest-only loopback ports, `auto_start=false`, `auto_start_agent=false`, `mobile_enabled=false`, `restart_on_crash=false`; managed updater enabled only in guest to exercise unreachable GitHub source. No plugin deployment to the production files. The Sandbox guest's networking must be verified **disabled**, not inferred from inability to reach one website.
- Inside guest: record actual GSC version/API health, start action submission, updater phase `error` / no applied updates when the repository is unreachable, Paper process/Java TCP local response after fresh startup, and graceful cleanup. Any missing proof is **INCONCLUSIVE/FAIL**, not PASS. Fresh Paper world can be generated inside guest; no live world/player traffic.
- Guest networking disabled means no real remote Java/Bedrock gameplay and no Geyser external mapping validation. Such E2E still belongs to 12.11.
- **Rollback/cleanup:** close Sandbox, removing guest VM and fresh world. Host's source files and networks untouched. Preserve only a sanitized sandbox summary in a **dedicated newly created output folder**, never write to source folders. Review cleanup/scope before any guest launcher is provided.

**If Sandbox is unsupported/not enabled:**
- Do not silently enable Windows optional features, Hyper-V, BIOS virtualization, WSL/WSB, Windows Firewall, or restart the host. Prepare a separately controlled **SubPC/VM disconnected from public network**, or pause actual offline boot with an explicit dependency. The already-passing code fixtures still demonstrate the narrow fail-open property.

## Exactly one server-PC capability check

The source-only tool `tools/day12/Day12_Phase7_Disposable_Sandbox_Capability_READ_ONLY.ps1/.cmd` checks:
- Host service running; Windows Sandbox executable + optional feature enabled; processor virtualization flag.
- Exactly one Playground Paper JAR candidate (matching conservative `paper*.jar` basename under configured backend folder), source folder exists.
- GSC Host executable referenced by the real Windows service, Java executable available and trusted **public** deployment key on disk.
- Minimum **8 GiB RAM and 8 GiB free disk** as conservative stage-planning bounds.

It performs **no** feature enable, VM creation, guest launch, binary copy, API request, server restart, policy/network adapter/firewall/DNS change, world/backup/cache modification. Reports **Boolean capability signals only**, never full paths, player data, tokens or machine names. `ISOLATED_SANDBOX_PREREQUISITES_PRESENT_NOT_EXECUTED` means prerequisites **look available**; it does **not** prove guest startup, safe operation of a chosen Java runtime, or real offline readiness. `SANDBOX_CAPABILITY_REVIEW_REQUIRED` means at least one prerequisite was absent or could not be read and should not be blindly changed to make the check pass.

After CI verification, the **operator will only be asked to run this one read-only check** on the real serverPC and upload `Day12-Sandbox-Capability-READ-ONLY.json`. If preflight passes, next engineering task is a standalone offline Sandbox guest run package with safe network-off preflight and teardown. The user will not have to repeat cache 84/84, Day12.7 Playground no-player precheck, Golden, LAN, Tailnet or GSC unauthenticated API tests.

**Status:** The strict 12.7 requirement is still `ACTUAL_OFFLINE_GSC_PAPER_STARTUP=NOT_PROVEN`. Other Day12.5/12.10/12.11/12.12 gates and Stable/Maintenance remain BLOCKED.
