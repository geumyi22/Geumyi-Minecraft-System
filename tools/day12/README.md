# Day 12 tools

Day 12 is the final production-hardening milestone. Tools are intentionally split into **READ-ONLY**, **dry-run**, **synthetic**, and **explicit-confirmation mutation** classes.

## Easiest later starting point

`Day12_Collect_All_READ_ONLY.cmd` collects every safe read-only report that can be gathered in one session. It does **not** create Golden backups, apply packs, restart anything, change policy, or build the known-good cache.

## Phase tools

- **12.0A** `Day12_Phase0_Golden_Baseline_READ_ONLY.cmd` — live baseline capture.
- **12.0B** `Day12_Phase0B_Golden_Checkpoint.cmd` — explicit-confirmation protected full Golden backups; all targets must already be offline.
- **12.1** `Day12_Phase1_Content_Preflight_READ_ONLY.cmd` — ResourcePack/DataPack/Geyser pack inventory. Live Java apply engine `Day12_Phase1_Managed_Content_Apply.ps1` is confirmation/offline/hash gated and auto-rolls back failed transactions; `Day12_Phase1_Managed_Content_Rollback.ps1` provides explicit manual rollback.
- **12.2** `Day12_Phase2_Component_Inventory_READ_ONLY.cmd` — component/update inventory.
  - `Day12_Phase2_5_Integrity_Security_READ_ONLY.cmd` — focused **server-PC read-only** fingerprint and security-scope evidence. Uses `deploy/components.json` as naming/version reference, hashes only matching in-place plugin JARs, and checks ACL role categories plus enabled inbound firewall port/protocol/remote scope. Output redacts server paths, identities, firewall rule names, program paths, remote addresses, passwords and tokens. Does **not** authenticate JARs against known-good release hashes or change production files. Version 2 checks canonical `ProgramData/GeumyiServerCenter/Runtime/Agent` (including configured Agent working directory under the managed root) to distinguish expected 0.5.4 JAR from legacy 0.4.5 candidate copies; recognizes Day10 Lobby GST/GDS filename aliases without assuming binary equality. Firewall `LocalPort=Any` is not represented as an explicit opening of each Minecraft port; program/service scope remains review-only. The firewall half now fails closed as `CHECK_REQUIRED` on query/partial-rule errors and records only a sanitized failure stage and exception class; do not interpret empty matching_rules as firewall safety if status is not `CAPTURED`. The default source of truth is still the original runtime `server.json` plus in-place JAR fingerprints, not an authenticated artifact signature.
- **12.3** `Day12_Phase3_Health_READ_ONLY.cmd` — whole-system health.
- **12.4** `Day12_Phase4_Storage_Log_DRY_RUN.cmd` — retention/log cleanup candidates only. After review, `Day12_Phase4_Lifecycle_Apply.cmd` moves eligible backups/logs to recoverable Trash areas (no permanent delete), and `Day12_Phase4_LogTrash_Recovery_Preflight.ps1` validates recovery material.
- **12.5** `Day12_Phase5_Security_Audit_READ_ONLY.cmd` — runtime listener/ACL/firewall exposure summary.
- **12.7** `Day12_Phase7_KnownGood_Cache.ps1` — Audit or explicit-confirmation Build; Build requires a Phase 12.0B PASS report.
- **12.8** `Day12_Phase8_DR_SYNTHETIC.ps1` — temp-only disaster-recovery drill used by CI.
- **12.10** `Geumyi_Final_Verification.cmd` — canonical final read-only verifier.
  - `Day12_Phase10_Bind_Evidence_READ_ONLY.cmd` — separate real-host, read-only evidence tool. Reads only the `server-ip`, `server-port`, `enable-rcon` and `rcon.port` fields from each backend `server.properties`; fingerprints the file and compares two Windows TCP listener snapshots. Non-loopback addresses and all credentials are redacted. It also samples GSC online state before/after listener discovery and probes localhost Java ports (TCP connect only); these probes cannot prove private binding. Its output is **CAPTURED_REVIEW_REQUIRED**, never a substitute for `Geumyi_Final_Verification.cmd` PASS. Missing listeners or blank `server-ip` must not be treated as private bind evidence.
  - `Day12_TCP_Bind_Diagnostic_READ_ONLY.cmd` — native Windows TCP listener/bind evidence collection for a fail-closed `backend_ports_private` investigation; synthetic Windows CI PASS does not prove live listener privacy.
- **12.12** `Day12_Phase12_Soak_READ_ONLY.cmd` — soak start/end snapshots.

## Recovery Kit

`recovery-kit/` contains hash-gated recovery helpers. The CI packs them as `Geumyi-Recovery-Kit.zip`. No plaintext credentials belong in the kit.

## Final release

`FINAL-RELEASE-GATES.json` is fail-closed. The final closure workflow only packages evidence after every repository and live gate has been explicitly changed to PASS. Final Stable publication is separately handled by `.github/workflows/day12-final-release.yml`, which re-runs safety/security/system/mobile build gates before publishing a signed immutable Stable release.

Historical Day 8–11 recovery evidence is intentionally retained.


### Phase 12.10: second-PC private-port exposure check

- `Day12_Phase10_LAN_Proof_READ_ONLY.cmd`: execute only from a **different Windows PC**, not the Minecraft host. Enter the server PC private IPv4 at the prompt. It reads/changes no firewall, server settings, service state, files or passwords.
- Checks public Java TCP 25565–25567 as positive controls and backend Java 25570–25573 plus RCON 25575/25576/25577/25579 for possible LAN access. All reports redact the server LAN IPv4, include no credentials, and are always `CAPTURED_REVIEW_REQUIRED`, never `PASS` for the final release.
- Private TCP CONNECTED = possible exposure, investigate before changes. NO_CONNECTION = inconclusive about binding; could be firewall or routing. Public ports all unreachable = remote control path unverified. Continue to require the canonical 12.10 verifier and live E2E evidence.


### Phase 12.5: ActiveStore broad-allow review

- `Day12_Phase5_Firewall_Scope_READ_ONLY.cmd`: one-time follow-up **on server PC only** after the combined 12.2/12.5 scan. Reads current firewall ActiveStore inbound enabled Allow rules, current network category set and active firewall profile policy; reviews the Any-port/Any-application TCP/UDP/Any-protocol subset against interface, address, service and security filters.
- No raw firewall rule name/ID, program path, private IP, host/interface name, token or username is exported. Any filter/query error is recorded as a bounded error category and the result stays `CHECK_REQUIRED`; a successful result is `CAPTURED_FOR_REVIEW`, **never a release/security PASS**. It cannot infer actual socket binding or WFP packet authorization. A full scan does **not** need to be repeated just to run this narrowed check.

### Phase 12.5: rule and ACL review

- `Day12_Phase5_Rule_ACL_Review_READ_ONLY.cmd`: one-time **server PC** follow-up after the ActiveStore policy capture. Examines only current ActiveStore inbound Allow rules with Any program+Any port (not a full redundant scan of all component hashes). Classifies local rule display strings **only in memory** to heuristic, non-verified categories; does not export firewall rule names/IDs, raw IPs, usernames or executable paths. 
- Reads **only NTFS ACL metadata** (not contents or credentials) for GSC ProgramData, `server.json`, Runtime, Runtime/Agent and Agent 0.5.4 JAR. Reports per-ACE mutating rights as explicit bit flags and role groups, not effective user permissions. Write actions and release-gate edits are forbidden; `CAPTURED_FOR_REVIEW` is not a 12.5 security PASS. The output JSON is private evidence, not a GitHub artifact.

#### Variable collision fix and directory-right gap (2026-10-09)

- Original 06:35 operator report's five `target_role` strings all displayed `BUILTIN_USERS` due to case-insensitive `$Role` parameter / `$role` local variable collision. The records are in deterministic order: GSC ProgramData dir, `server.json`, Runtime dir, Runtime/Agent dir, Agent 0.5.4 JAR. Corrected source uses `$principalGroup` and asserts role label preservation on an already-created temp directory in synthetic Windows CI.
- The ACL collector now also emits `delete_children` from NTFS `DeleteSubdirectoriesAndFiles` bit for directories. `server.json` and Agent JAR direct BUILTIN_USERS ACL had no mutating Allow in the **06:35 capture**, while parent GSC/Runtime directory inherited ACEs allow creation. Parent `DeleteChild` and effective access **were not covered by the old report**; no access changes approved. Full firewall rules/ActiveStore scan already CAPTURED and need not be repeated for this fix.

### Phase 12.5: minimal ACL-only follow-up (no firewall loop)

- `Day12_Phase5_ACL_Only_READ_ONLY.cmd` runs `Day12_Phase5_Rule_ACL_Review_READ_ONLY.ps1 -AclOnly`. Read-only, **server PC only**, five configured GSC file and directory ACLs. No 266-rule ActiveStore enumeration, API request, TCP test, Java/JAR modification, or backup scan.
- Verifies all five output target labels remain uncorrupted, captures NTFS `DeleteSubdirectoriesAndFiles` as `delete_children` separately from child-file `Delete`, emits `firewall_enumeration=NOT_EXECUTED_ACL_ONLY`, and reports `CHECK_REQUIRED` on any missing/failed ACL. This mode cannot prove a user's effective access or grant permission to modify ACLs.

### Phase 12.5: corrected real-host ACL-only capture (2026-10-09 06:43)

- The `-AclOnly` command produced an actual server-host report with `acl_target_label_consistency=true`, five CAPTURED target-role labels, `delete_children` bit present, zero target errors and `firewall_enumeration=NOT_EXECUTED_ACL_ONLY`. Thus the 06:35 role-label variable collision is verified fixed in live evidence, not just CI.
- No reason to rerun the same ACL or full firewall collectors. Three parent directories still have inherited BUILTIN_USERS file/dir creation Allow; direct `server.json` and Agent 0.5.4 JAR file ACEs do not grant ordinary-user content modification. Full effective access and the need for broad firewall rules remain under review. Review `DAY12-PHASE5-SECURITY-REVIEW.md` at repo root before suggesting any future production security change.

### Phase 12.10: Windows Native Basic/Owner listener evidence

- `Day12_Phase10_Native_Listener_Crosscheck_READ_ONLY.cmd`: run on the **server PC** as administrator once. Uses read-only `GetExtendedTcpTable` OWNER_PID_LISTENER IPv4 and IPv6 plus BASIC_LISTENER IPv4. Reports only target ports, redacted address scopes and bounded provider statuses; no credentials/host addresses or executable paths. CI starts a temporary loopback listener to verify both IPv4 classes; that synthetic test is not a real server proof.
- The canonical `Day12_Final_Verification_READ_ONLY.ps1` now integrates the native provider. `backend_ports_private` remains fail-closed unless there are observable loopback-only TCP listener rows for **every online Java and corresponding RCON** port plus a complete native provider capture. A reachable loopback socket, server.properties `server-ip=127.0.0.1`, or negative LAN connect tests **cannot** replace listener evidence. Nonloopback addresses are redacted in the canonical output. Do not rerun legacy whole-system collectors merely to compare native OS table classes.

### Day 1–12 Windows PC temporary cleanup (separate from Day12 release gates)

- **One-click menu:** `Geumyi_Day1To12_PC_Temp_Cleanup.cmd`. Tool: `Geumyi_Day1To12_PC_Temp_Cleanup.ps1`; instructions: `DAY1-12-PC-CLEANUP-GUIDE.md` in repository root.
- **Preview is the only default action.** Scans only project-name-matching direct children of current user's TEMP/TMP/LOCALAPPDATA Temp. Desktop/Downloads are inventory-only and never quarantined. Days 1–7 require explicit `Geumyi-DayN-` names; unprefixed generic names are not treated as Geumyi. Existing day 8–11 known scratch names are recognized conservatively.
- Reviewable **local private plan** → exact approval phrase to quarantine eligible temp directories, minimum age 7 days and 24-hour plan, revalidation of each folder, reparse/protected-data guards, same-volume moves, **pre-journal manifest for crash recovery**, restore-to-original without overwrite.
- **Day12 cleanup always held until final release closure**; GSC/GSCM installations, ProgramData, active servers/worlds, Golden/protected backups, recovery, logs/crash, cache and JARs are excluded. Even quarantine does not free space until a distinct 14-day retained quarantine's permanent purge is explicitly approved. No automatic Windows-wide junk cleanup or final Day12 PASS.
- CI runs synthetic name/protected-object classification and isolated Windows preview → quarantine → restore; do not infer the tool was executed on the user's host.

### Phase 12.10: scoped live local TCP reachability (not a bind-proof substitute)

- `Day12_Phase10_Loopback_Compare_READ_ONLY.cmd`: use on **server PC**, ordinary privilege. After 01:12 live native Basic/Owner capture found only `25570` and `25579` loopback among online required ports, this tool probes only `127.0.0.1` Java+RCON TCP handshakes for GSC-online services. One connection per service port, no RCON auth or Minecraft protocol, no global firewall/native scan, and no config/backup mutation. A brief handshake may appear in logs.
- Output `Geumyi-Day12-Loopback/Day12-Loopback-Compare-*.json`. A positive TCP result determines **reachability**, not listener bind scope or authenticated protocol functionality. Native observation gaps and the canonical `backend_ports_private` fail-closed gate remain until direct listener proof and new canonical FAIL=0.

### 12.10 active connection hold — diagnostic for invisible LISTEN sockets

- `Day12_Phase10_Active_Connection_Trace_READ_ONLY.cmd` examines only the four still-unobserved **online** listener ports 25571/25573/25575/25576 after operator-reported local TCP 6/6. It briefly connects from server PC to `127.0.0.1:<port>`, holds the TCP client socket open during `Get-NetTCPConnection -State Established`, `netstat -ano -p TCP`, and .NET active TCP endpoint queries, then disconnects. No data frames, authentication, RCON commands, service restarts, or firewall/ACL/config writes; brief connections may appear in logs.
- Reports coarse local/remote endpoint scopes and a PID-present Boolean, never PID value, usernames, IPs other than loopback, executable paths, token contents or command lines. Synthetic CI uses a controlled temporary loopback TCP listener and actual accepted socket. **ESTABLISHED observation does not prove the listening socket accepts loopback only** and never opens the canonical Day12 backend_ports_private release gate by itself.

### Phase 12.10 — provider-difference read-only diagnostic

Run `Day12_Phase10_Provider_Diff_READ_ONLY.cmd` once on the server PC to compare Windows native TCP LISTENER and ALL classes, filtered/unfiltered NetTCPIP queries, and a sanitized netstat exit status. Only the unresolved 25571/25573/25575/25576 ports are included. No TCP connections are opened and no services, worlds, backup, firewall or configuration are changed. A Windows synthetic controlled-listener test passed. The report is not a release PASS; `backend_ports_private` remains fail-closed.

### Phase 12.10 — GetTcpTable2 IPv4 independent API corroboration

- After the 2026-10-10 01:43 live `Day12-Provider-Diff-20261010-014337.json` showed a `25571` loopback listener in native LISTENER classes but 0 matches in native ALL and unfiltered CIM, and 0 listener rows for `25573/25575/25576`, use `Day12_Phase10_TcpTable2_READ_ONLY.cmd` for one **targeted independent Windows API** crosscheck.
- Reads only `GetTcpTable2` `MIB_TCPTABLE2` (IPv4), three short snapshots of the six GSC-online Java+RCON ports; emits only port, coarse address scope and sanitized status. No network connections, services, firewall/ACL, world, config, backups or credentials touched. An ephemeral CI loopback listener validates the P/Invoke layout and wildcard classifier.
- A missing IPv4 row is inconclusive; an observed IPv4 loopback row does not alone prove IPv6 private binding or future state. The result **never promotes canonical `backend_ports_private`, 12.10, or Stable**. Do not keep repeating the 12.5 security, Golden, 6/6 loopback or LAN 0/8 tests.

### 12.10 — process/config provenance preflight (no TCP scan)

- `Day12_Phase10_Process_Bind_Preflight_READ_ONLY.cmd`: actual SERVER PC, normal user privileges. This is a **new hypothesis check**, not a repeat TCP listener poll, TCP connection test, firewall audit or GSC E2E. Reads selected harmless settings from GSC `server.json` and four `server.properties` files in memory, Java/GSC process family/count and heuristic command-line-to-profile path matches **without exporting paths or command-line content**, plus aggregate IP interface compartment metadata.
- `Get-NetIPInterface -IncludeAllCompartments` checks interface metadata, not TCP socket placement, and no `Get-NetTCPConnection -IncludeAllCompartments` argument is asserted. Reports are redacted and a Windows synthetic fixture verifies that RCON passwords are excluded. A process-path hint is **not** authoritative bind attestation, so this tool never clears the `backend_ports_private` FAIL or approves production restart. Source: `DAY12-PHASE10-BIND-DECISION-REPORT.md`.

### 12.10 — read-only per-server application startup logs

- `Day12_Phase10_Startup_Log_Bind_READ_ONLY.cmd`: server PC, ordinary privileges. Only reads first **6MiB** of each profile's current `logs/latest.log` through a bounded, shared-read file handle. Looks for Paper's Java `Starting Minecraft server on ADDRESS:PORT` and `RCON running on ADDRESS:PORT` startup messages. Maps addresses to LOOPBACK/WILDCARD/NON_LOOPBACK_REDACTED/UNKNOWN without exporting raw log text, IPs, passwords, usernames or paths. No network packet, firewall/ACL, config, server or world mutation.
- Missing/rotated/truncated startup messages are UNKNOWN. A detected wildcard/nonloopback RCON or Java entry requires security review. A LOOPBACK startup announcement is **application historical bind intent, not authoritative current socket listen scope** and cannot alone override `backend_ports_private=FAIL`. CI synthetic data checks wildcard classification and no secret export. Further context: `DAY12-PHASE10-GSC-SOURCE-AUDIT.md`.

### 12.12 soak — safe multi-Java process identity comparison (prepared, not run live)

- `Day12_Phase12_Soak_READ_ONLY.cmd` Start → server/client use over 8–12 h where practical → End. The revised v2 report compares identical **process name + PID + start time**, not the first Java process with the same name. New/terminated/restarted Java processes have **no invented memory delta** and are counted separately.
- Start and End refuse to overwrite existing evidence in the selected `SessionDir`. Use an explicitly new directory for another session; retain original `soak-start.json`, `soak-end.json` and `FINAL-SOAK-REPORT.json`. Missing process start times mean identity continuity is **unverified**.
- The report's duration flag is `DURATION_MET_REVIEW_REQUIRED` after >=8 hours, not stability PASS. Final soak requires review of logs, in-game function, Java/Bedrock, host/GSCM stability and resources. This is source/CI preparation only; no real soak has started.
