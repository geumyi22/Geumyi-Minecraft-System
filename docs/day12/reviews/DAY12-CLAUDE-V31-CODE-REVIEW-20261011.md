# Day 12.10 Claude v3.1 — GPT-6 source review (2026-10-11)

Input: operator-provided `Geumyi-Day12-Claude-v3.1-Findings-20261011.zip` and Claude's markdown findings. ZIP contains `Day12_ListenStateProbe_v3_1.ps1`, `Start_Day12_ListenStateProbe_v3_1_READ_ONLY.cmd`, findings, and SHA256SUMS. All three checksums match actual bytes: PS1 `1d35a7d05ad6df98b9cea2c2139d25c6f0db5b855d0d4f800828f626993289ad`; CMD `e4bb758f1de3c8fba4410c20fed5bde2e7dc89515622acf52cff12f3fefc6790`.

## Working hypothesis (not root-cause proof)

The v3 report saw successful IPv4/IPv6 loopback bind, client connect and accept, while every observer enumerated zero probe LISTEN rows, and three process-level non-LISTEN rows matched each probe port rather than the two expected ESTABLISHED legs. Claude proposes the third row is the bound listener but with raw `dwState != 2`, which v3 filtered away. The earlier netstat-vs-native delta is **not** by itself enough to prove that specific state-code corruption. Other OS, kernel, filtering and harness causes remain open.

## Static code review

- v3.1 uses one native GetExtendedTcpTable snapshot for AF_INET and AF_INET6; parses raw state/ports/PID, compares an owned temporary IPv4 and IPv6 self-connected TcpListener to synthetic listener signature, reports state and owner-role aggregates. API constants `MIB_TCP_STATE_LISTEN=2`, `ESTAB=5`, `TIME_WAIT=11` agree with Microsoft Tcpmib documentation.
- The listener *signature* (remote wildcard + port 0, excluding ESTAB/TIME_WAIT) is a **heuristic**, not equivalent to Windows's state LISTEN or kernel-level bind proof; its use in `signature_backend` must not bypass strict privacy gate.
- `Get-Verdict` requires probe states, remote_port_zero and matching own PID for an odd-state classification, but does **not additionally require** remote wildcard / exactly one candidate / independent accept-count match. An odd-state result therefore remains an evidence lead rather than a conclusive OS defect attribution.
- Native query return codes are exported; non-zero return values do not independently abort script with exit failure. Treat any such result as inconclusive even if tool emits exit 0 (exit 0 means report created, **not PASS**).
- Synthetic SelfTest and C# 5/PSScriptAnalyzer checks were reported by Claude under PS7 Linux; actual Windows PowerShell 5.1, native marshaling, cmd.exe and cleanup of private compilation folder remain **NOT EXECUTED** on user host. GPT-6 did not execute script under Windows; script source and checksums reviewed.
- No production service stop/restart, firewall/ACL/adapter/world/backups changes in inspected source. The tool does start/close two temporary loopback listeners and clients, compiles managed C# in a uniquely named TEMP folder, deletes that private folder, and creates a Desktop report; do not describe as making literally no OS/filesystem changes.

## Decision

Recommend **one** user-run Windows 5.1 diagnostic with existing v3.1 CMD, retain script and output report, check `probe_v4.native.raw_states`, `probe_v6.native.raw_states`, candidate scope/owner/remote port, `native.v4/v6.return_code`, and `verdict`. Do not rerun older diagnostics, change Windows build or disable security tools. Keep `backend_ports_private=FAIL_UNVERIFIED_NATIVE_OWNER_ADDRESS`, `stable_release_allowed=false` unchanged.
