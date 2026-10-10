# Day 12.7 — Controlled offline known-good startup: approved PRECHECK only

## Intent and consent

Operator replied `dd` to a proposal to **prepare and execute a safety-bounded Day12.7 offline-start test** with Golden 4/4 protection. The answer supports **preparing the test** and a read-only live readiness precheck. It is not an instruction to cut every user's Internet access, modify Windows Firewall/ACL, reinstall GSC, shut down all four servers, or overwrite backup/world files without a narrower execution design.

**Already tested and NOT repeated:** real server-PC cache **84/84 SHA-256+size MATCH**, zero missing/corrupt/duplicate/reparse files (operator `Day12-Cache-Integrity-READ-ONLY.json`); Golden 4/4 protected; LAN/Tailnet 0/8 backend remote connections per tested path; GSC unauthorized API 8/8 HTTP 401. These are meaningful positive results but **do not establish actual offline GSC/Paper start**.

## Readiness precheck prepared for SERVER PC

After focused Windows CI succeeds, download `day12-phase7-offline-readiness-kit` from its workflow and extract fully. **On the SERVER PC only**, double-click `Day12_Phase7_Offline_Start_Readiness_READ_ONLY.cmd`. Do not use the SubPC. Upload only `Desktop\Geumyi-Day12-Offline-Readiness-*\Day12-Offline-Readiness-READ-ONLY.json`.

The script uses **only** four authenticated-by-existing-local-policy GSC HTTP GETs on `127.0.0.1:8790`: `/api/v1/snapshot`, `/api/v4/update/fleet`, `/api/v1/servers/playground/players`, and `/api/v4/backups?id=playground`. It does not send a token, execute an RCON command, POST to a job queue, disconnect a NIC, alter DNS, add/remove a firewall rule, stop/restart GSC/Paper, upload files, modify a backup or create/restore a world.

It checks all of the following:
- Exact expected GSC Host **4.3.8** and Windows GSC Host service **Running**.
- GSC **0 active jobs**; target **Playground** exactly one fleet entry and currently ONLINE.
- Live target Minecraft query confirms **0 connected players**. Unknown or offline state is **not** zero.
- Target has at least one GSC `scope=full`, `protected=true`, `verified=true`, `trashed=false` backup.
- Explicit safe, non-automatic update policy `hold` or `manual`; no `block_start=true`, pending/rolling_back/downloading/blocked or unknown updater phase. **A managed policy that says current is NOT automatically safe** because a fresh pre-start check can update plugins on next start.

The JSON returns `PRECHECK_GUARDS_MET_NO_TEST_PERFORMED` only if *all* checks succeed; otherwise `BLOCKED_NEEDS_SAFETY_REVIEW` with limited, sanitized reason codes. **Neither result** changes the actual Day12.7 offline-start gate. No IP, server path, player name, backup filename, API secret, raw response body or PID is exported.

## Required separation before any disruptive live test

1. Prefer **disposable staging**: isolated world/config copy and a startup instance using known-good cache and explicitly unreachable update source, with no production listener/port collision. Only test when the staging mechanism has a verified rollback/teardown path and known Java/Paper/Geyser compatibility. This repo package does **not yet create a staging VM, download a source artifact or initiate a local proxy**, and such work must not be falsely labelled performed.
2. If staging is not possible, prepare a **single-server Playground scoped maintenance window**, with no players/jobs, verified Golden backup, exact manual/held updater configuration, pre-test log capture and an agreed rollback timeline. The operator's earlier allowance of ordinary single-server restarts does **not** authorize changing host-wide network configuration or firewall policies.
3. Only then create an independently gated `DISRUPTIVE_EXECUTION` step with **explicit test-specific confirmation string, narrow network effect, watchdog recovery, before/after connectivity and service verification, and no automatic repeat**. Do **not** affect the household's router, disable Windows Ethernet/Wi-Fi/Tailscale, adjust ACL/firewall just to manufacture an outage, or alter protected Golden archives.
4. Confirm actual offline-source failure and actual GSC/Paper startup, no unexpected plugin update, eventual restoration and real Java/Bedrock functionality. Record client and process observations. If any ambiguity, stop and mark `INCONCLUSIVE`; do not change `FINAL-RELEASE-GATES.json`.

**Current progress:** `phase_12_7_cache_byte_integrity=PASS_REAL_HOST` and **`phase_12_7_offline_known_good_startup=OPEN`**. Native Java/RCON ownership, effective 12.5 security, 12.11, 12.12 and Stable/Maintenance remain BLOCKED. This kit performs **PRECHECK ONLY**, not the actual outage and not a real offline-start PASS.

## Offline Go behavior that is already tested but not equivalent to real network outage

`GSC/ServerCenter/cmd/host/updater_offline_prestart_test.go` disposable Go CI verified that local missing trusted release key leaves existing JAR intact and pre-start does not unnecessarily block normal startup; explicit `hold/manual` similarly preserve installed JARs. A truly **unrecoverable interrupted transaction** intentionally blocks startup. This is source-level prestart behavior, not a host disconnection.


## 2026-10-10 10:58:57 KST — ACTUAL Playground offline-start PRECHECK blocked solely by auto-update policy

- Operator submitted real private `Day12-Offline-Readiness-READ-ONLY.json`, report `schema=1`, `synthetic=false`, `read_only=true`, target `playground`, `result=BLOCKED_NEEDS_SAFETY_REVIEW`. **Exactly one reason** `AUTOMATIC_UPDATE_POLICY_MUST_BE_REVIEWED`.
- Confirmed **GSC Host 4.3.8 Running**, 0 active jobs, one unique Playground profile ONLINE, verified 0 connected players, at least one protected+verified+full backup, update phase included in accepted non-transactional states, and `block_start=false`. The only unsatisfied readiness predicate was `update_policy_nonmanaged=false`, meaning **policy is not demonstrably `hold` or `manual`**. The sanitized report does not reveal the exact policy value: DO NOT label it definitively `managed` until verified separately.
- `network_outage_initiated=false`, `service_restart_performed=false`, `production_config_mutated=false`, `backup_world_cache_modified=false`, `offline_start_e2e_proven=false`; **no production changes**. Do not call the precheck a failure of GSC or Playground; the guard did its job. **Do not ask the operator to rerun it unchanged**.
- Safety decision: **do not change the running Playground update policy automatically** merely to make the test green. Avoid NIC/firewall/host-wide network outage, Java/RCON port interference or rolling restart for this test. Prepare **disposable isolated update-source interruption** with a verified rollback/no-port-conflict plan, or seek separate narrow production update-policy and outage approval if no safe staging route is available.
- Added [Go disposable updater HTTP transport failure test `GSC/ServerCenter/cmd/host/updater_offline_prestart_test.go`](https://github.com/geumyi22/Geumyi-Minecraft-System/blob/main/GSC/ServerCenter/cmd/host/updater_offline_prestart_test.go): valid ephemeral Ed25519 public key, managed-policy pre-start updater with HTTPS GitHub round trip **intercepted to return a deterministic "update source unreachable" error**, assert 1 actual attempted metadata request, `Phase=error`, `BlockStart=false`, `Applied=0`, **previous JAR bytes unchanged** in t.TempDir(). This is stronger than missing-public-key or `manual` test but **still not an actual running Paper/GSC host offline-start E2E**. No production network operation or script download.
- Real cache SHA256 **84/84 previously PASS** and Golden **4/4 protected**; do not repeat. 12.7 full offline-start still **OPEN**, 12.5 effective ACL/security, 12.10 native owner/bind, 12.11 full E2E, 12.12 soak, Stable/Maintenance also BLOCKED. CI proof status will be updated only after completed green run.
