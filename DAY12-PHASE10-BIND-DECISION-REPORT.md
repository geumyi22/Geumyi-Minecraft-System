# Day 12.10 — backend bind evidence decision report

> Status: **OPEN / FAIL-CLOSED**. Production listener-only binding not fully proved. No deployment or live-service action is authorized by this report.
>
> Last operator evidence: **2026-10-10 01:51 KST**; read-only, real-server, not synthetic.

## Why this report exists

Repeated user-run Windows TCP listener inventories do not agree with successful Java/RCON local connectivity. A missing table row is **not** evidence of external exposure or of a non-running server, but positive loopback connections and negative remote-LAN tests are **not** evidence of exclusive loopback binding. Do not lower the `backend_ports_private` gate simply to clear a workflow.

The read-only data-gathering stage for this anomaly is **saturated**. Further repetitions of the same TCP table scanners without a changed hypothesis would add little confidence. Advance via a **controlled, explicitly approved production-maintenance bind/ownership investigation**, not more blind scans.

## Source-indexed, time-scoped evidence

| Local date and artifact | Scope | Findings and limits |
|---|---|---|
| Oct 9 final verifier (last genuine canonical run) | Final Day12.10 gate | **18 PASS / 0 WARN / 1 FAIL**. Only `backend_ports_private` FAIL. Verifier was later improved with native API, but **not rerun on this real host**. |
| Oct 9 second Windows PC LAN check | Network reachability, different host | Public Java **3/3 reachable**, private Java+RCON **0/8 reachable**. Proves only the tested LAN vantage at that time, not exclusive listener binding or arbitrary Internet reachability. |
| Oct 10 01:12 `Day12-Native-TCP-20261010-011258.json` | Windows native IPv4/IPv6 Owner + IPv4 Basic LISTENER, 2 rounds | `25570` Wild Java and `25579` Lobby RCON **`127.0.0.1` LISTEN** observed in both rounds. Other ONLINE service ports not seen. Management API `8787` wildcard IPv4+IPv6 listening (separate authenticated service boundary). Wild/Playground/Lobby ONLINE, Other OFFLINE. |
| Oct 10 01:19 `Day12-Loopback-Compare-20261010-011956.json` | Server-PC TCP client handshakes | **6/6** online Java/RCON services accepted localhost connections: `25570`, `25571`, `25573`, `25575`, `25576`, `25579`. Does not prove listening exclusivity. |
| Oct 10 01:27 `Day12-Active-Connections-20261010-012751.json` | Held localhost ESTABLISHED snapshots | `25573`, `25575`, `25576` showed server-side loopback/loopback ESTABLISHED entries; `25571` connected but lacked a captured ESTABLISHED row. The netstat collection reported generic ERROR, later narrowed by separate diagnostics. |
| Oct 10 01:43 `Day12-Provider-Diff-20261010-014337.json` | Windows LISTENER / ALL / CIM / netstat differential | `25571` **loopback LISTEN** observed by two IPv4 LISTENER classes; `25573`, `25575`, `25576` not seen. IPv4 native ALL unexpectedly observed no targets, CIM filtered returned `NO_MATCHING_INSTANCE`, netstat ran successfully (exit 0) but did not capture a target listener. |
| Oct 10 01:51 `Day12-TcpTable2-20261010-015103.json` | **GetTcpTable2 IPv4-only**, three snapshots | **3/3 API runs CAPTURED**, no errors, but **0/6 target listener rows** in every sample — including 25570 and 25579 previously observed loopback with a different API at a different time. Report `CAPTURED_REVIEW_REQUIRED`, `mutation_performed=false`, `secrets_exported=false`. This is inconclusive. |

### What we know

1. The Minecraft service status from Oct 10 earlier captures had Wild, Playground and Lobby online, Other intentionally offline. This is not a proof of current uptime at arbitrary later times.
2. Six online Java/RCON TCP endpoints were locally reachable at 01:19. Some listener bind addresses were separately observed on loopback, at **different** times. Do not aggregate these into a fictitious simultaneous positive proof of all six exclusive listener addresses.
3. No wildcard/non-loopback private backend listener was observed in the supplied snapshots. This is **absence of positive exposure evidence**, not blanket proof of safety.
4. `server.properties` from earlier scoped binder evidence reported `server-ip=127.0.0.1` across the four managed server profiles. A configuration file can diverge from the actual running process binding or RCON listener; the canonical gate correctly requires runtime evidence.
5. The official Windows `GetTcpTable2` API is an IPv4 TCP table. It does not establish IPv6 binding.
6. The repeatedly empty/mismatching TCP tables might have process lifetime/compartment/collection/API interpretation causes. None is confirmed by this evidence. Do not assert compromise, service failure, a Windows platform defect, or a specific application bug.
7. The 01:51 report does not carry a host identity. **On 2026-10-10 the operator explicitly confirmed that `Day12_Phase10_TcpTable2_READ_ONLY.cmd` ran on the actual Minecraft SERVER PC, not the client/sub PC.** This settles the host-vantage ambiguity by operator attestation; it does not repair the missing runtime LISTEN rows or prove an OS defect. The report also does not expose total OS TCP rows, only the six target matches.

## Decision

- **Keep `backend_ports_private` FAIL**, hence Day 12.10 OPEN, 12.11/12.12 not yet completed and 12.13 Stable blocked.
- Preserve Golden 4/4 checkpoints, cache, world data, installer baselines and prior evidence. Do not clean Day1–12 scratch until project closeout.
- **Stop repeating** the native LISTENER, ALL, `GetTcpTable2`, netstat, loopback handshakes, LAN 0/8, Golden backup and 12.5 firewall/ACL reports without a new reason.
- No changes to Windows firewall, port forwarding, services, RCON passwords, `server-ip` or GSC/GSCM binaries on the strength of these reports alone.

## Proposed next phase: controlled ownership and bind attestation

This requires a **separate operator approval and maintenance window** for anything touching live services:

1. **Environment confirmation: SATISFIED by operator attestation** (actual server PC, 2026-10-10). Do not repeat the question or request identifying machine data.
2. **Preflight (READ ONLY):** review existing GSC fleet/PID provenance, running executable's actual bind arguments/config source, process compartment/context, Paper and RCON effective bind behavior, Windows IPv4/IPv6 listener ownership. Avoid writing full process command lines, paths or credentials to reports; require traceable redacted scopes and owner-category classifications.
3. **Selectively isolate only if needed:** use an approved disposable/staging environment first to establish an authoritative bind attestation for Paper Java and RCON, with a documented rollback. Production restart or service isolation **requires user authorization** and preflight that the existing Golden recovery checkpoint is intact; do not regenerate or overwrite it.
4. **If production change becomes necessary:** capture before state, stop/restart only the expressly approved server(s) after player-presence check, keep service interruption minimal, and abort/rollback on health change. Never touch live world/save state without approved procedure.
5. **Revalidation:** run the updated canonical `Geumyi_Final_Verification.cmd` **once** after a real fix or fresh authoritative binding evidence. Only mark 12.10 PASS if all mandatory checks actually pass with supported evidence. Then proceed with pending 12.5 security approval, 12.11 Java/Bedrock/GSCM actual E2E and 12.12 soak; 12.13 Stable only after release gates all pass.

## Source documents

- [Day 12 Live Runbook](DAY12-LIVE-RUNBOOK.md)
- [Day 12 Repository Progress](DAY12-REPO-PROGRESS.md)
- [Day 12 Phase 5 Security Review](DAY12-PHASE5-SECURITY-REVIEW.md)
- [Final release gates](FINAL-RELEASE-GATES.json)

Operator JSON reports are sensitive host evidence and are not published as source-controlled attachments.

## References

- Microsoft, [GetTcpTable2](https://learn.microsoft.com/en-us/windows/win32/api/iphlpapi/nf-iphlpapi-gettcptable2) and [MIB_TCPTABLE2](https://learn.microsoft.com/en-us/windows/win32/api/tcpmib/ns-tcpmib-mib_tcptable2)
- Microsoft, [GetExtendedTcpTable](https://learn.microsoft.com/en-us/windows/win32/api/iphlpapi/nf-iphlpapi-getextendedtcptable)
