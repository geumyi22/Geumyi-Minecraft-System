# Day 12.10 — GSC native TCP PID attribution fail-closed hardening (2026-10-11)

## Purpose and constraints

Operator instructed continuation without repeated approvals until genuinely new server-PC execution is necessary. This is **repository-only security engineering** based on existing scoped host evidence: Windows 26220 PowerShell 5.1 listener inventories often reported raw state 0; Claude v3.1 own IPv4/IPv6 test listeners corroborated state-0 listener-like signatures; 6/6 online Java/RCON backend ports were observed in that limited scope, while `other` was offline. The canonical **all eight** port requirement is still `FAIL_UNVERIFIED_NATIVE_OWNER_ADDRESS`.

No operator device, Windows firewall, ACL, GSC service, Paper/Velocity process, backup or world was modified. The live GSC baseline remains **4.3.8**; this source fix is **NOT** an installed update or a versioned release.

## Newly found source safety issue

In `GSC/ServerCenter/cmd/host/proc_windows.go`, the old `portPID(port)` scanned `GetExtendedTcpTable` rows returned by `TCP_TABLE_OWNER_PID_LISTENER`, but accepted the *first matching local port regardless of `dwState`*. A malformed/non-listener row could therefore misattribute a PID, impacting `rememberServerProcess` lifecycle tracking and the explicit `forceStopServer` path in `cmd/host/main.go`. This is a **credible false-attribution risk in source**, not evidence of a prior wrongful process kill.

**Fix:** `portPID` now delegates to `listenerPID`, whose existing predicate requires `dwState == MIB_TCP_STATE_LISTEN (2)`. If no owner-positive LISTEN record is available, the lookup returns an error instead of guessing. The existing controlled listener test remains, and new Windows real-loopback regression tests assert that an **ESTABLISHED client's ephemeral local port** cannot be returned as a listener owner for either IPv4 or IPv6 and invalid ports fail closed.

This fail-closed approach can result in **unavailable owner attribution** on the operator's unusual state-0 OS, instead of treating state-0 as a trusted process-kill target. That is intentional until reliable independent owner proof exists. It should not be described as repairing or explaining the OS's anomalous TCP state code. Other force-stop sources (tracked PID, Java stats) still require their own caution/authorization; no forced live action was performed.

Microsoft documents `MIB_TCP_STATE_LISTEN=2`; state `0` is **not a defined LISTEN state**: <https://learn.microsoft.com/en-us/windows/win32/api/tcpmib/ns-tcpmib-mib_tcprow_owner_pid>. Table-class `TCP_TABLE_OWNER_PID_LISTENER` is documented as returning listening endpoints: <https://learn.microsoft.com/en-us/windows/win32/api/iprtrmib/ne-iprtrmib-tcp_table_class>. Neither statement establishes a Windows 26220 kernel defect; raw state-0 remains an unresolved observed anomaly.

## CI evidence

- Source change commit `1c97c5d07aad44d923b0e04349e8d2654e8c03fb`.
- Windows regression tests commit `29aec87aa8efb8abe022a036e4230b85c05dc804`.
- [Day 11 Windows Host Test Package #38076599198](https://github.com/geumyi22/Geumyi-Minecraft-System/actions/runs/38076599198): **SUCCESS**; `go test ./...`, Host and Client Windows builds passed. This confirms **normal hosted-Windows process table behavior and the negative client-local-port regression**, not the operator Insider build.
- [Day 12 Security SBOM Reproducibility #38076599202](https://github.com/geumyi22/Geumyi-Minecraft-System/actions/runs/38076599202): **SUCCESS**.
- [System CI #38076599208](https://github.com/geumyi22/Geumyi-Minecraft-System/actions/runs/38076599208): status should be checked before claiming complete System CI success (the separate Windows Host suite above is already green).

## Existing live evidence scope and safe next actions

- **Pass only bounded operational evidence**: controlled v3.1 state-0 probe owner/loopback signatures and 6/6 currently online game/RCON socket rows (Wild, Playground, Lobby), prior application startup bind intent 8/8, tested LAN/Tailnet negative reachability 0/8 and 401 unauthenticated API responses.
- **Still open**: native unequivocal LISTEN state and all eight simultaneous live bind/owner rows; `Other` was offline. Existing 12.5 broad Allow owner and inherited Users-Create ACE need separately authorized effective-policy review. Existing 12.7 CI offline update-source test and 12.11 disposable process recovery do not prove operator live outage or signed canary E2E.
- **Do not** ask for another identical netstat/GetTcpTable/provider scan or repeat successful Java/Bedrock/GSCM behavior tests. Do not silently start Other or restart Paper to manufacture an eighth-row result.
- The next justified Windows runtime action requires a **new evidence mechanism** capable of excluding wildcard/nonloopback for all online and eventual Other backend listeners; if this implies a service start or policy change, demand explicit safe operator authorization and rollback first.
- Leave `FINAL-RELEASE-GATES.json` untouched. **Stable and Maintenance promotion BLOCKED**, `backend_ports_private=FAIL_UNVERIFIED_NATIVE_OWNER_ADDRESS`.

This record is source-safety engineering progress, not Day 12.10 completion.
