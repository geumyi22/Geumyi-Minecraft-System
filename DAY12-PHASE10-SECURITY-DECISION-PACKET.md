# Day 12.10 — security closure decision packet (operator approval required for any policy change)

**Prepared 2026-10-10; review only; NO LIVE CONFIGURATION OR SECURITY GATE CHANGE.**

## What is already established

| Evidence | Scope | Outcome |
|---|---|---|
| `Day12-Process-Bind-20261010-020508.json` | On-disk GSC/server.properties | **4/4** configured Java `server-ip` on loopback; all 8 planned Java/RCON ports and RCON enabled. No `rcon.ip` key observed. |
| `Day12-Startup-Bind-20261010-022013.json` | Current per-server log, at time of each start | **Java/RCON 8/8** startup messages report `LOOPBACK`. All log captures nontruncated. **Other log ~69 h old** and Other was previously OFFLINE, so do not call all eight ports currently listening. |
| 01:19 server-PC local TCP check | 3 online servers | Java+RCON **6/6** accepted 127.0.0.1 TCP handshakes. |
| 01:12, 01:43 Windows Native LISTENER | Positive but incomplete | Loopback listener rows observed on 25570, 25571, 25579 on different captures. Not all six online ports. |
| Earlier second-PC LAN test | One external LAN vantage | Public 3/3 reachable, private Java/RCON **0/8 reachable** from that location. Does not prove Internet/Tailscale/IPv6 isolation. |
| 01:51 `GetTcpTable2` | IPv4 table, server PC | **0/6** target listener rows despite 3/3 query CAPTURED, contradicting other evidence; not proof of offline/exposure. |
| Day12.5 Security | Firewall and local ACL inventory | **OPEN**: broad allows and directory-create rights need an explicit risk review; unauthenticated API probe 401 on inspected endpoint only. |

## Technical diagnosis from GSC sources

`getServerStatus` calls `tcpOpen(127.0.0.1, JavaPort)` for ONLINE; GSC's Windows `portPID` and `nativeTCPListener` also rely on a TCP table view that has yielded intermittent omissions. Paper/RCON startup logs are a different and valuable **application-side** source, but neither startup logs nor local connects prove **contemporaneous exclusive socket bind**.

## Options

**A. Strict current gate — preferred where reliable host attribution is available.** Capture contemporaneous OS/kernel listener addresses (IPv4 **and** IPv6) and owner attribution for each ONLINE Java/RCON port with a tested, reliable method; prove all are loopback and no public wildcard/other bind. Re-run canonical verifier once. If unavailable in this environment, the gate remains FAIL; **do not restart production repeatedly** just to make an inconsistent diagnostic report nonempty.

**B. Compensating network-control security case — requires deliberate approval of a documented change in validation policy.** In lieu of direct OS bind proof, authorize only a narrowly scoped alternative based on application startup logs, configured loopback Java bind, RCON management behavior, verified Windows firewall effective rules (including previously unclassified broad allows), actual nonloopback reachability across required LAN/overlay/IPv6 vantage points, and regression/rollback. A single LAN 0/8 test is **insufficient**. The operator must understand residual uncertainty, and a separate implementation must continue to FAIL CLOSED when any required input is missing or stale. **Do not silently edit `backend_ports_private` to PASS or weaken the existing canonical validator.**

**C. Leave this gate OPEN.** If neither strict proof nor a reviewed compensating policy is supported, treat the instance as operationally reachable locally with useful security signals, but **do not claim Day12.10 secure closure or release Stable**. Non-live CI, docs, recovery-kit and soak-test preparation can continue without changing runtime.

## Update after one successful Playground restart (2026-10-10 02:47)

- Protected verified full backup, zero players, no active jobs and safe update state were demonstrated on server PC. One GSC graceful Playground restart was accepted/completed, server returned ONLINE. Immediately subsequent Windows Native OWNER_PID/BASIC LISTENER queries CAPTURED but again could not observe Java 25571 or RCON 25576.
- **A plain restart is not a viable proven path to strict-positive bind evidence. Do not repeat it.** Source API layout review (`DAY12-PHASE10-WINDOWS-TCP-API-AUDIT.md`) did not reveal an obvious struct/offset bug. No actual root cause, public exposure or exclusive loopback ownership is established.
- The standing operator permission covers ordinary one-server restarts with safety preconditions, but not broad/high-risk security changes. Use remaining preapproved work for GitHub, CI, readiness and non-disruptive test design.
- Maintain options A/B/C, with current choice C (strict gate OPEN). An adequate alternative requires materially different and trustworthy evidence, not simply accepting old 8/8 application logs as new positive OS binding observations.

## Independent WFP audit proposal — 2026-10-10

- A distinct **existing Windows Security Event Log** source is now available: `5154` listener permitted and `5158` bind permitted, including the historical source address, target port and process identity. Unlike `GetExtendedTcpTable`/`GetTcpTable2`, it is generated by Windows Filtering Platform auditing. It requires auditing to have already been enabled at the relevant event time.
- Dedicated read-only tool: `tools/day12/Day12_Phase10_WFP_Audit_Attestation_READ_ONLY.cmd`; security classifier and non-export of raw IP/paths/PIDs validated by Windows synthetic fixture. **Day12 Safety CI 37977424905 PASS**; **Operator Kit 37977424871 PASS**. Real server-PC WFP report has **NOT** yet been supplied.
- Correlating WFP event address/PID/time against the still-running Java generation can strengthen the application-log proof without more TCP scans, but **still cannot independently prove no additional active listening sockets or IPv6 exposure**. Absence of WFP records may be caused by disabled auditing, log retention or permissions.
- Do not change `auditpol` or security policy simply to make this check succeed. If WFP evidence is missing/incomplete, the strict gate remains OPEN. If it reveals wildcard/nonloopback binds, review immediately before further operations. Keep the original decision alternatives A/B/C unchanged and **never promote Stable automatically**.
- [WFP read-only scope and evidence interpretation](DAY12-PHASE10-WFP-READONLY-PLAN.md).

## Production-safety rule and operator handoff

- User explicitly allows autonomous **source inspection, GitHub changes, documentation and synthetic CI** without repeated check-ins.
- Stop before **any** host execution, reboot, service shutdown/start, world restore, firewall/ACL/port/bind mutation, RCON secret handling or security policy adjustment. Provide the user a concrete scoped operation, service impact, Golden 4/4 prerequisite, abort condition and rollback before requesting explicit permission.
- **No host operation is needed merely to store today's 8/8 app-side log result.** No repetition of the same listener scans, native calls, localhost connects, process categorization or application log parsing unless the environment actually changes.
- 12.11 client E2E, 12.12 real 8–12 h soak, 12.13 Stable and Day1–12 cleanup remain separately gated. The revised 12.12 soak tool has a **Windows synthetic CI PASS**, not a live-soak PASS.

## References

- [Day 12.10 bind decision](DAY12-PHASE10-BIND-DECISION-REPORT.md)
- [GSC source audit](DAY12-PHASE10-GSC-SOURCE-AUDIT.md)
- [Day 12.5 security review](DAY12-PHASE5-SECURITY-REVIEW.md)
- [Final live E2E checklist](FINAL-E2E-REPORT.md)
- [Final release gates](FINAL-RELEASE-GATES.json)

Private per-host JSON and raw server logs are not checked into GitHub.
