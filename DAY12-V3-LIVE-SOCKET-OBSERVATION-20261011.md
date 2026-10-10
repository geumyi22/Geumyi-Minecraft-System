# Day 12.10 — Claude v3 live Windows read-only socket observation, 2026-10-11 KST

Operator-submitted redacted JSON `DAY12-CLAUDE-REVIEW-SHARE-ONLY-THIS.json` (2026-10-11 02:46 KST), source v3.0.0 SHA-256 `bb5d9f311568ebd18f40f43a8edfbc5d4fd4db69a07d1b6060d322a30b63c957`. No private PIDs, addresses, commands or tokens copied into repo.

## Observed facts
- Windows PowerShell 5.1 Desktop, OS build 26220 (PS version 5.1.26100.9587), admin x64 FullLanguage, one default network compartment. This matches the Windows Insider Beta build branch 26220.9587 announced by Microsoft 2026-10-02; **no kernel defect attribution established**.
- IPv4 and IPv6 temporary loopback TcpListener instances started and self-connected successfully; probe lifetime spans both snapshots (400 ms apart). `native`, `netstat`, `.NET IPGlobalProperties` and `Get-NetTCPConnection` each saw neither **LISTEN** probe in A or B. All captured established loopback connection rows (2–3 per family). Hence the problem is **LISTEN endpoint enumeration/inventory**, not failure to create/con-nect own loopback sockets.
- Each provider reported IPv4 LISTEN=9, IPv6 LISTEN=0; native GetExtendedTcpTable (v4/v6) returned 0, native GetTcpTable (v4) returned 0, with IPv4 1008 endpoint entries including 825 TIME_WAIT; netstat parsed 959 TCP rows and had 0 unparseable. Network socket APIs share Windows providers; these are **not four independent kernel-level pathways**.
- GSC API is reachable on loopback, v4.3.8 running, settings/snapshot/fleet available and expected config port mismatches=0. Yet no observer found the API 8790, public Java ports 25565/25566/25567, or private game/RCON ports 25570–25573,25575–25577,25579.
- GSC fleet online: wild/playground/lobby, other offline. Process roles: PAPER=3, VELOCITY=6 (three Velocity parents of Velocity; 2 distinct command lines), STATUS_AGENT=1, other=0.
- In v3 `Test-ProbeInRows`, `owner_is_this_process` is evaluated only after LISTEN found: false therefore does **not** prove PID mismatch. Do not interpret a missing socket as evidence it is not actually listening.

## Interpretation / release gate
- Confirmed: diagnostic shows a credible live TCP LISTEN **observation gap**, with physical sockets able to accept connections. Potential Windows Insider build bug, common API table provider filtering, security hooks/NSI or additional code issues remain **hypotheses, not proven roots**.
- `backend_ports_private=FAIL_UNVERIFIED_NATIVE_OWNER_ADDRESS`, `stable_release_allowed=false`, `maintenance_allowed=false` unchanged.
- Existing LAN/tailnet four-path negative tests, user-accepted Java/Bedrock game features and 12.12 operational-soak acceptance stay scoped-valid; no replay requested.
- No restart, firewall/ACL/adapter, world/backup, or production service mutation performed.
- Next action: targeted independent review of native table/parser and OS/build/security hypotheses; don't repeatedly ship the same netstat wrappers, don't assert a Windows kernel defect without discriminating evidence. Preserve gate until credible host socket bind proof or an approved alternative verification method.

Microsoft Insider announcement: https://blogs.windows.com/windows-insider/2026/10/02/announcing-new-builds-for-2-october-2026/
