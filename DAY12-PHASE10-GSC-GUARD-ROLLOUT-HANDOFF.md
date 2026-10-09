# Day 12.10 — GSC Guard rollout handoff: first operator action is READ ONLY

**Status 2026-10-10 05:18 KST:** Real-host read-only guard compatibility **4/4 PASS, 0 errors**, source CI PASS; unsigned preview candidate CI in progress. Canonical `backend_ports_private`: **FAIL**, unchanged. **Do not install/restart/update production GSC yet.**

## What is already done autonomously

1. Hardened GSC backend startup preflight for the **four reserved Day12 IDs**. It now requires the corresponding GSC profile Java and RCON ports, the on-disk Java/RCON port values, `enable-rcon=true`, and an **exact** `server-ip=127.0.0.1`. The exact IPv4 loopback value is required because the current GSC status/console paths call `127.0.0.1` (accepting arbitrary loopback `127.0.0.2` or `::1` would break management even if the address were private). This is a **pre-launch configuration guard only**; no present socket proof.
2. Rejected ambiguous or shadow duplicate critical Java properties, escaped-key aliases and port drift with Go unit tests. All other non-Day12 profiles remain outside the extra guard.
3. **Source commit `c3f0894e03c3c181487b1cc142d5b7d19c637cfa`:** [Host Test workflow #37985531392](https://github.com/geumyi22/Geumyi-Minecraft-System/actions/runs/37985531392) **SUCCESS** and [System CI #37985531374](https://github.com/geumyi22/Geumyi-Minecraft-System/actions/runs/37985531374) **SUCCESS**, including GSC Go tests/build.
4. Added a distinct **one-shot read-only operator precheck** `tools/day12/Day12_Phase10_GSC_Guard_Rollout_Precheck_READ_ONLY.ps1/.cmd`. It examines the existing `%PROGRAMDATA%\GeumyiServerCenter\server.json` and four server folders' `server.properties` in memory, returns **only** per-ID port and key anomaly categories, not paths, passwords, tokens or host IPs. It never connects a socket, starts/stops a process, edits firewall/audit policy or installs GSC.
5. **Precheck Windows Safety CI #37985723489: SUCCESS**, plus the precheck synthetic test for valid profiles, duplicate-IP shadows, changed RCON port, nonloopback server IP and Java escaped-key ambiguity. Day12 Operator Kit #37985700059 (same read-only files): SUCCESS; a focused two-script ZIP + README + SHA256SUMS was extracted from that CI artifact and CRC/SHA checked.

## Operator evidence received — 2026-10-10 05:18 KST

The user completed the requested one-shot read-only compatibility CMD and supplied `Day12-GSC-Guard-Precheck-20261010-051837.json`, generated at `2026-10-10T05:18:37.8921445+09:00`.

- `synthetic=false`, `read_only=true`, `result=CONFIG_COMPATIBLE_REVIEW_ONLY`, `issue_count=0`, `error_category=NONE`.
- 4/4 profiles compatible: `wild` Java/RCON **25570/25575**, `playground` **25571/25576**, `other` **25572/25577**, `lobby` **25573/25579**; all `compatible_for_guard=true`, each `issue_codes=[]`.
- `configuration_modified=false`, `windows_policy_modified=false`, `service_modified=false`, `server_restarted=false`, `secrets_exported=false`.
- `backend_ports_private=UNCHANGED_FAIL`. This is a *configuration compatibility* result only, not current socket ownership/binding evidence, not Java/RCON uptime proof and not a green Stable authorization.
- **Do not ask to rerun the same precheck without a relevant profile/config change.** The user's first requested operator action is complete.

## Next GitHub-only stage — distinctly versioned preview

- A new **`4.3.9-rc.1` UNSIGNED review-only preview** is built from a temporary copy of baseline source via `tools/day12/Build_Day12_GSC_Guard_RC_CI.ps1` and `.github/workflows/day12-gsc-guard-rc-preview.yml`.
- The disposable CI job first requires System CI and verified GST/GDS/StatusAgent payloads; it checks Go tests, builds uniquely stamped Host/Client/Setup preview EXEs, runs non-destructive Host self-test, hashes all files, ensures main's tracked `4.3.8` source is untouched, and archives an artifact explicitly marked **DO NOT INSTALL**. No signed manifest/Stable release and no production host mutations.
- After CI conclusion is verified, prepare signed release and installation/rollback options, with exact offline backup/Golden+player+update preflight. Any live GSC update still requires separate operator authorization and an appropriate deployment maintenance window.
- Source `4.3.8` stays the deployed/baseline identity. **Never distribute a modified binary that claims to be the shipped 4.3.8**.
- The *previous* Windows TCP provider mismatch remains unresolved; the preventive startup guard does not establish current `backend_ports_private` and cannot lift the strict gate.

## Historical operator instructions (already completed; DO NOT REPEAT)



On the **Minecraft SERVER PC**, extract the focused kit to a new folder and run `Day12_Phase10_GSC_Guard_Rollout_Precheck_READ_ONLY.cmd` once. Upload the newest **`Desktop\Geumyi-Day12-GSC-Guard\Day12-GSC-Guard-Precheck-*.json`**. If exit code 2, `CHECK_REQUIRED`, or a missing server profile appears, **do not edit server files manually**: provide the JSON as-is. A result `CONFIG_COMPATIBLE_REVIEW_ONLY` means the on-disk config appears compatible with the new guard, not a real bind or security PASS.

This input is necessary before distributing any new GSC executable because stricter preflight may block starting a server when its profile ports differ from what is on disk. Prior 02:05 evidence showed `server-ip=127.0.0.1` and expected ports, but did **not** include duplicate critical-key semantics or a contemporaneous all-four source-v3 compatibility result.

## Once the operator JSON is reviewed

- If any mismatch or ambiguity: determine which file/profile is affected using non-secret categories, **propose exact minimal changes** with a backup and rollback plan, and obtain separate explicit approval before touching live server config. No automatic edit.
- If all four are compatible: prepare a **distinctly versioned, non-Stable GSC candidate** (do NOT disguise modified binaries as the shipped `4.3.8`). Review installer/self-update behavior, version compatibility, selective update, protected Golden state, user sessions and backout. **Operator approval** is required before GSC install/apply or host reboot.
- Following any approved installation, perform host smoke test, public Java/Bedrock/GSCM checks and mandatory bind/owner security verification independently. The unresolved Windows TCP provider gap remains open; even successful config compatibility or new GSC preflight **must not** change `backend_ports_private=FAIL` or prematurely start Day12.13 Stable.
- Do not create new backups, delete anything, change Windows Firewall, enable WFP auditing, rerun old listener scans, or force a server restart merely to get a PASS.

## Separation of assertions

`CONFIG_COMPATIBLE_REVIEW_ONLY`: existing file/profile consistency.  
`GSC source + CI PASS`: code unit/build contract on GitHub runner.  
`backend_ports_private=FAIL`: current private Java/RCON socket binding/owner not yet independently proven.  
`Stable`: BLOCKED pending actual independently verified production release gates.
