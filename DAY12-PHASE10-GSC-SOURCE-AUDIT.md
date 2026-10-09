# Day 12.10 — GSC source audit: ONLINE, ownership and Java/RCON bind

**Scope:** repository-only review. **Status:** source behavior identified; live exclusive bind **NOT VERIFIED**, final `backend_ports_private` **FAIL remains**. No live server, firewall or Golden data changed.

## What the source actually does

| Behavior | Source | Meaning for this investigation |
|---|---|---|
| Server startup validation | `GSC/ServerCenter/cmd/host/main.go` `startServer` → `v4_core.go` `runV4Preflight` | Validates directory, start command, Java runtime and Java port consistency; **does not independently verify actual socket bind address**. Do not label its green status private-binding proof. |
| Server launch | `GSC/ServerCenter/cmd/host/lifecycle.go` `startServerLocked` → `launchCommand` → Windows `shellCommand` | Runs configured batch in the **server folder as current working directory**; Java command line can legitimately use a relative `-jar` and not contain the absolute server path. The earlier 0/10 path-matches are inconclusive, not proof of rogue processes. |
| GSC server ONLINE state | `main.go` `getServerStatus` | Sets `JavaPortOpen` and `Online` from `tcpOpen("127.0.0.1", javaPort)`. It proves local TCP handshake success **only**; neither owner PID nor loopback-exclusive listener scope. |
| Java process ownership | `lifecycle.go` `rememberServerProcess` → `proc_windows.go` `portPID` | Uses `GetExtendedTcpTable(..., TCP_TABLE_OWNER_PID_LISTENER)`. If the same OS table misses a live listener, **process ownership can also be unknown or fail**, even when local TCP connect succeeds. This dependency is proven by code, not yet demonstrated to have caused a production control operation to fail. |
| RCON management health | `main.go` `getServerStatus` | Uses passive cached listener/native observation **OR authenticated RCON success for current backend lifetime**. Authenticated command usability does **not** prove remote socket isolation. |
| RCON traffic | `main.go` `bootstrapRCONHealthAsync` and `runServerConsoleRCON` | Targets **127.0.0.1** RCON; connecting to loopback does not rule out a wildcard second bind. RCON security must be assessed separately from Java `server-ip`. |
| TCP listeners in GSC | `proc_windows.go` `listenerPID` | Uses Windows IP Helper OWNER_PID_LISTENER tables; prior operator snapshots show some target ports inconsistently omitted. Do not infer OS/API defect, process compromise or exposure until independently reproduced. |

## Operator evidence preserved (not committed raw)

- October 10 01:12 and 01:43: specific Java/RCON LISTEN loopback rows observed at different times (`25570`, `25571`, `25579`).
- 01:19: **all six online Java/RCON ports** responded to explicit `127.0.0.1` TCP connects on SERVER PC.
- 01:27: three server-side ESTABLISHED loopback endpoint observations, distinct from listener binding.
- 01:51: `GetTcpTable2` IPv4 captured **0/6** of those ports in three snapshots on SERVER PC, per explicit operator attestation.
- 02:05: all four on-disk `server.properties` Java `server-ip` keys configured to loopback, expected Java/RCON ports and enabled RCON; **RCON bind address itself not attested**, and no `rcon.ip` setting observed.
- Separate-PC previously established 0/8 local private backend ports reachable from that LAN vantage. This verifies a **specific tested network-path restriction**, not exclusive service bind.

## Source-informed decision

1. **Do not modify or override the canonical `backend_ports_private` gate.** Keep 12.10 OPEN, 12.13 stable blocked; preserve Golden/known-good/source traceability.
2. **Stop polling the same TCP tables.** Repeating listener/PID read methods that depend on the same OS view adds little information.
3. **Next non-disruptive, distinct data source:** parse the application's existing current `latest.log` startup announcements, independently for **Java listener and RCON listener**, returning only expected-port match + `LOOPBACK/WILDCARD/NON_LOOPBACK/UNKNOWN` categories. Implementation: `tools/day12/Day12_Phase10_Startup_Log_Bind_READ_ONLY.ps1/.cmd`. It never exports raw log content; regex may not match all versions, so missing evidence is **UNKNOWN**.
4. **If Java or RCON reports wildcard/nonloopback startup:** treat as security review. Do not loosen firewall, expose ports, change Java/RCON config or restart automatically. Review exact policy and a staged rollback, then request explicit operational approval if necessary.
5. **If application reports loopback:** useful additional evidence of start-time intent, still not an independent proof of **current** exclusive OS socket ownership. A controlled maintenance-window/live attestation or a separately approved equivalently strong segmented-network security policy may be necessary. It must not silently weaken the prior required standard.
6. **Final sequence after positive proof:** rerun canonical read-only verifier once, reconcile remaining 12.1/12.2/12.5/12.7/12.9 live work, proceed 12.11 real Java/Bedrock/GSCM E2E → 12.12 soak → 12.13 Stable → user-approved Day1–12 temp cleanout.

## 2026-10-10 02:20 real host application log result

- Four configured profiles' present `latest.log` files independently reported **LOOPBACK** for Java **and** RCON startup binds, **8/8 startup message checks present** and no detected wildcard/nonloopback message.
- Observed last-write ages in the operator-provided sanitized result: Wild/Playground ~11 min; Lobby ~60 min; Other ~69 h (offline in earlier GSC fleet). The tool did not export raw log lines, process IDs, usernames, passwords or addresses.
- This confirms **Java+RCON start-time application claims**, directly addressing the earlier RCON ambiguity; it is not a new claim of simultaneous live sockets. The very stale Other log must **not** be used to claim currently-online RCON.
- Existing `backend_ports_private` canonical gate is still FAIL because it explicitly requires positive runtime OS LISTEN bind evidence. Preserve that release block. Repeating the same diagnostics or altering a known-good server merely to make the scanner pass is not justified. Any controlled owner/bind attestation requires operator-approved maintenance and rollback.

## Post-restart native API source audit (2026-10-10 02:47)

- One real Playground graceful restart completed and returned ONLINE; the two target OS listener entries remained `NOT_OBSERVED` even immediately after restart. This confirms **a restart is not a demonstrated remedy for this evidence gap**.
- SDK crosscheck in `DAY12-PHASE10-WINDOWS-TCP-API-AUDIT.md`: GSC's Go IP Helper `GetExtendedTcpTable`, the separate PowerShell/.NET helper, and the IPv4-only `GetTcpTable2` reader use row sizes/offsets consistent with the published TCP structs. No obvious static decoding error found, but **root cause remains unverified**.
- Avoid more same-method diagnostics, arbitrary Windows changes or a weakened canonical PASS. App 8/8 start-loopback evidence stays valid but historical; current socket owner/bind proof remains missing. **12.10 OPEN, Stable blocked**.

## No-action boundaries

This is repository analysis plus an optional scoped **read-only application-log** reporter. No server starts/stops, world writes, settings edits, Windows ACL/firewall changes, RCON credential access/export, backup deletion, or Stable promotion. A GitHub CI green result validates only the synthetic fixture, not the live host.

Links: [Day 12.10 bind decision](DAY12-PHASE10-BIND-DECISION-REPORT.md), [Day 12 runbook](DAY12-LIVE-RUNBOOK.md), [Final release gates](FINAL-RELEASE-GATES.json).
