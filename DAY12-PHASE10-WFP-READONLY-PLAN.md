# Day 12.10 — independent Windows WFP bind/listen audit evidence

**Prepared:** 2026-10-10. **Scope:** operator-controlled, read-only audit of previously recorded Windows Security events. **No production execution claimed.**

## Why this differs from repeated TCP scans

Previous `GetExtendedTcpTable`, `GetTcpTable2`, `Get-NetTCPConnection` and netstat inventory captured inconsistent and missing LISTEN rows for operational Java/RCON ports. Repeating them did not resolve exclusive private bind ownership.

Microsoft documents Windows Filtering Platform (WFP) **Security Event 5154** (listener permitted) and **5158** (local bind permitted) as independent *event-time* evidence containing process ID, application name, source address and port:

- [Windows audit 5154](https://learn.microsoft.com/en-us/previous-versions/windows/it-pro/windows-10/security/threat-protection/auditing/event-5154)
- [Windows audit 5158](https://learn.microsoft.com/en-us/previous-versions/windows/it-pro/windows-10/security/threat-protection/auditing/event-5158)
- [WFP auditing](https://learn.microsoft.com/en-us/windows/win32/fwp/auditing-and-logging)

This proposal **reads existing events only**. It **does not** enable/disable audit policy. Audit-policy changes are out of scope because WFP success auditing can be high-volume, may affect security log retention, and require separate approval.

## Tool and output

`tools/day12/Day12_Phase10_WFP_Audit_Attestation_READ_ONLY.cmd` invokes the PowerShell reader on the server PC. The script checks only the eight planned private TCP Java/RCON ports:

| Backend | Java | RCON |
|---|---|---|
| Wild | 25570 | 25575 |
| Playground | 25571 | 25576 |
| Other | 25572 | 25577 |
| Lobby | 25573 | 25579 |

It server-side filters Windows Security events for these port numbers and 5154/5158 within the most recent seven days. It correlates each event PID and timestamp to the **current Java/javaw process generation** (to exclude reused PIDs). It exports **only service, port, coarse address scope, event counts and conservative finding** into `Desktop\Geumyi-Day12-WFP\Day12-WFP-Bind-*.json`. It intentionally does **not** export raw IP, path, PID, process command line, raw logs or secrets.

### Interpretation

- `HISTORICAL_LOOPBACK_LISTEN_AND_BIND`: both 5154 and 5158 for a currently running Java process generation, with only loopback scopes in the sampled event set. **Historical corroboration, not final security PASS.**
- `HISTORICAL_LOOPBACK_PARTIAL`: only one event kind observed. Not final PASS.
- `REVIEW_NON_LOOPBACK_OR_UNPARSEABLE`: any included event was wildcard, nonloopback or unparseable; requires security review.
- `NO_CURRENT_PROCESS_EVENT`: missing matching record, could be disabled audit, aged-out log, process not running, or a limitation of enumeration. **Not an offline or safe verdict.**
- `UNAVAILABLE`: Security log not readable, query failed or insufficient rights. **Not an error in the game server.**
- `EVENT_QUERY_TRUNCATED`: report has insufficient coverage; no inference about absent binds.

The query is historical and bounded, not continuous. A missing external bind event is not proof of no external listener: capture may be disabled/incomplete or a different process may own another endpoint. Even a historical pair of 5154/5158 loopback events **does not prove no additional current sockets** (including IPv6). Process PID generation correlation is useful but insufficient alone.

**Absolute invariant:** this tool NEVER changes `backend_ports_private`, `FINAL-RELEASE-GATES.json`, or stable/maintenance mode. Canonical Day12.10 remains **FAIL** until a separately approved, sufficient live-attestation method establishes exclusive private binding and process ownership for each online port.

## Operator handoff (only after CI PASS)

When the Windows synthetic test and packaging both pass, one optional, read-only capture on the actual **server PC** is appropriate. Reading the Security log may require opening the CMD as administrator. If it reports missing records, **do not enable auditpol or repeatedly restart servers**; record the limitation and proceed to an evidence-based alternative decision. The CMD does not stop/restart servers, modify security configuration, or touch worlds, backups and saved credentials.

## Synthetic regression criteria

Windows synthetic test constructs 5154/5158 XML records for loopback IPv4 and IPv6, wildcard binds and a stale PID, then exercises the parser and classifier **without querying Security log or opening any TCP listener**. Failing case must not be scored PASS. Source code and CI compilation do not count as on-host runtime evidence.

## Remaining release blockers

Windows TCP listener table discrepancy; separate complete Day12.11 operations/reboot E2E; 8–12h live soak; then, and only then, Day12.13 Stable release. Do not repeat completed client smoke checks or protected Golden backup checks simply to make a report look fuller.
