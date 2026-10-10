# Day 12.10 — GSC native listener-owner fail-closed hardening and state-0 compatibility (2026-10-11)

## Corrected source interpretation — IMPORTANT

The deployed GSC 4.3.8 has NOT been changed on the operator server. This is repository source/CI work only.

The `portPID` function calls `GetExtendedTcpTable` using **TCP_TABLE_OWNER_PID_LISTENER (class 3)**, which Microsoft's SDK explicitly defines as a **listener-only** table. Therefore the initial suggestion that choosing a local-port match unconditionally selected an ordinary ESTABLISHED client PID was **too broad and not supported by this API contract**. The actual operator's Windows 26220 raw TCP state **0** for the known self-owned listener was observed with controlled IPv4+IPv6 TCP sockets. Requiring `dwState == 2` inside `portPID` would break the operator's currently observed listener mapping, with possible lifecycle/force-stop tracking regression.

**The first interim patch** commit `1c97c5d` made that overly strict change; **it was superseded** by a corrected state-0-compatible implementation in commit `16911d1fafce2a3fa9ffdea7612f4c727a801729`. The interim green CI run `38076599198` does not establish the final implementation's test status.

## Final design

- Preserve `portPID`'s listener-class query for both IPv4 and IPv6 without making a *raw state 2* requirement. The table class is the API-defined listener qualifier.
- Reject invalid local port values and PID `0` / missing owner PID.
- If two or more returned listener rows for the queried port have **different PIDs**, fail closed with ambiguous-ownership error rather than returning the first process. Multiple matching rows owned by the **same PID** remain valid (including dual-stack binding).
- Separate `listenerPID` still uses raw state 2 for memory/stats and has **not** been broadened to 0; `nativeTCPListener` is therefore still subject to the provider-state anomaly. We intentionally do not convert state-0 signatures into a global security PASS.
- Windows tests: actual IPv4/IPv6 listener PID matches self; an ephemeral connected client local port is rejected; malformed ports rejected; pure synthetic PID conflict/zero/same-owner cases fail closed.

**Scope of risk reduction:** helps prevent a PID conflict from silently selecting the wrong process in lifecycle management or an explicitly requested force-stop. This is **a defensive improvement**, not evidence that PID conflicts or incorrect process kills occurred on the actual host.

Microsoft primary sources:
- <https://learn.microsoft.com/en-us/windows/win32/api/iprtrmib/ne-iprtrmib-tcp_table_class>
- <https://learn.microsoft.com/en-us/windows/win32/api/tcpmib/ns-tcpmib-mib_tcprow_owner_pid>

## CI and staged changes

- Corrected implementation: `16911d1fafce2a3fa9ffdea7612f4c727a801729`.
- Latest Windows tests: `f8ad22c2af2189c1566e0b3b03e65688f9c8f18d`.
- Exact CI run links must be read for the **latest** source commit, not the earlier `29aec87` commit. Windows Host, System CI and Security/SBOM run status for the corrected implementation must be independently verified before announcing PASS.
- No operator server restart, forced kill, ACL/firewall/network change, backup/world mutation, Host install, auto-update, signed Canary publication or Stable promotion.

## 12.10 security evidence (unchanged)

Operator's live redacted v3.1 03:01 KST report: three ONLINE Paper instances Wild/Playground/Lobby each showed one IPv4 loopback and owned Java+RCON raw-state-0 native signature (6/6), `other` OFFLINE and its 25572/25577 absent. Controlled self-owned IPv4/IPv6 listeners corroborated raw-state-0 listener signatures, but this does not prove all eight live private binds or the root cause of Windows provider state 0. Prior scoped LAN/Tailnet IPv4/IPv6 remote tests found 0/8 private connects with positive public controls; other network paths/effective WFP still require separate security proof.

**Canonical `backend_ports_private=FAIL_UNVERIFIED_NATIVE_OWNER_ADDRESS`, stable/maintenance=false, remains unchanged.** No repeated netstat or forced production restarts are justified without a genuinely different evidence mechanism.
