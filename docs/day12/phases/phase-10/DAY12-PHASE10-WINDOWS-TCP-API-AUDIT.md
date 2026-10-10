# Day 12.10 — Windows native TCP listener source audit after scoped restart

Status: **repository + Microsoft SDK documentation review, not live listener validation**. Dated 2026-10-10. No production mutation by this audit.

## What changed on the server

`Day12-Scoped-Restart-20261010-024734.json` confirms **Playground-only GSC graceful restart accepted and completed, ONLINE before and after**; preconditions included 0 players, no active jobs and a protected verified full backup. Immediately afterwards, the one permitted `GetExtendedTcpTable` scoped native check returned **CAPTURED** but **NOT_OBSERVED** for Java port **25571** and RCON port **25576**. These two missing entries remain unknown bind state, not evidence of exposed/wildcard listeners. Another restart for the same hypothesis is **not justified**.

## Side-by-side source review

| Source | Native API use | SDK layout crosscheck | Outcome |
|---|---|---|---|
| `GSC/ServerCenter/cmd/host/proc_windows.go` `listenerPID` | `GetExtendedTcpTable(AF_INET/AF_INET6, TCP_TABLE_OWNER_PID_LISTENER=3)` | IPv4 MIB_TCPROW_OWNER_PID fields and 24-byte stride; IPv6 MIB_TCP6ROW_OWNER_PID 56-byte stride, localPort +20, state +48, PID +52 | These offsets match SDK declarations. **No obvious static row-offset explanation** for the live missing port entries. |
| `tools/day12/Day12_Native_TCP_Provider_READ_ONLY.ps1` | .NET P/Invoke `GetExtendedTcpTable`: OWNER_PID IPv4+IPv6, BASIC_LISTENER IPv4; ALL variants for diagnostic only | IPv4 BASIC 20 bytes, OWNER_PID 24 bytes; IPv6 OWNER_PID 56 bytes. Local port from network-order first two bytes of 32-bit DWORD; state=2 means LISTEN | Struct/class selection and principal byte offsets appear consistent with SDK. **An OS table request CAPTURED does not prove it included all expected endpoints.** |
| `tools/day12/Day12_Phase10_TcpTable2_READ_ONLY.ps1` | `GetTcpTable2` IPv4-only, three snapshots | `MIB_TCPROW2` 7 DWORD fields => 28 bytes; state first, local address +4, port +8, PID field +20 | The layout matches the documented row structure, but all six watched targets were absent from the 01:51 real-host check. It cannot attest IPv6. |
| `tools/day12/Day12_Final_Verification_READ_ONLY.ps1` | Native/PowerShell/.NET/netstat listeners combined | Mandatory private listener gate requires a positive address entry for **each online Java and RCON port** and rejects any non-loopback address. | Keeping the gate fail-closed is correct until a reliable authoritative/current security proof is acquired. Do not let an empty table become `PASS`. |

**Limitation:** This source audit checks definitions/offsets and available snapshots; it does **not** establish whether the discrepancy is caused by network compartments, endpoint enumeration, Windows provider behavior, privileges, timing, transient paths, service ownership or some other cause. Those hypotheses remain unverified. A restart after the 02:41 preflight code fix **did not** make target listener rows visible.

## Why the evidence is not circular

- GSC `ONLINE` confirms a `127.0.0.1` Java TCP handshake, not exclusive bind.
- Paper's earlier per-server `latest.log` startup announcements independently report **Java+RCON LOOPBACK 8/8**, including stale Other, not a current OS row for every listener.
- A second Windows PC previously could not reach eight private backend ports from its LAN network vantage, but it cannot prove all possible IPv6, overlay, forwarding or Internet paths.
- GSC `listenerPID` and Day12's Windows native helper both use the **same underlying IP Helper family of OS tables**, so do not count them as independent kernel-level confirmations.

## Decision after the successful one-server restart

1. **Do not restart Playground a second time simply to attempt another listener listing.** No proven production code bug, OS defect or security exposure justifies an uninformed change.
2. The canonical `backend_ports_private` gate remains **FAIL**. Day 12.10 **OPEN**; no Stable deployment and no Day1–12 host cleanup.
3. Allow autonomous source/CI/static E2E planning. The next *meaningfully different* live validation would need to prove active ownership and bind scope without depending on the same incomplete OS table, or build a separately reviewed firewall/IPv6/overlay compensating-control case. This requires a concrete design and local user execution, **not** another clone of these TCP scanners.
4. A future backend start/restart performed for an actual operational reason should be followed by normal GSC status and live client health testing, but should not claim the Windows native inventory must suddenly return matching rows.
5. 12.11 real Java/Bedrock/GSCM E2E, 12.12 actual 8–12 h soak, and 12.13 Stable all remain **PENDING LIVE / BLOCKED** where dependent on security closure.

## SDK source references

- [GetExtendedTcpTable API](https://learn.microsoft.com/en-us/windows/win32/api/iphlpapi/nf-iphlpapi-getextendedtcptable)
- [TCP_TABLE_CLASS enumeration](https://learn.microsoft.com/en-us/windows/win32/api/iprtrmib/ne-iprtrmib-tcp_table_class)
- [MIB_TCPROW_OWNER_PID layout](https://learn.microsoft.com/en-us/windows/win32/api/tcpmib/ns-tcpmib-mib_tcprow_owner_pid)
- [MIB_TCP6ROW_OWNER_PID layout](https://learn.microsoft.com/en-us/windows/win32/api/tcpmib/ns-tcpmib-mib_tcp6row_owner_pid)
- [MIB_TCPROW2 layout](https://learn.microsoft.com/en-us/windows/win32/api/tcpmib/ns-tcpmib-mib_tcprow2)
