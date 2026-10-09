# Day 12.10 — independent SubPC IPv4+IPv6 reachability check (read-only)

**Status: SOURCE/CI PREPARATION, NOT LIVE PROOF.** This is a strictly scoped **new IPv6-inclusive second-host check**; it does not repeat the old host TCP table / Security log / application startup scan. The canonical `backend_ports_private` gate remains **FAIL** irrespective of this result.

## Exact task when the assistant asks the operator to execute

**Computer:** Windows **SubPC**, not the Minecraft server PC. A GSC Host service detected on the current computer forces the launcher to refuse running.

**Files together:** `Day12_Phase10_SubPC_DualStack_Exposure_READ_ONLY.cmd` and `Day12_Phase10_SubPC_DualStack_Exposure_READ_ONLY.ps1`, from the tested read-only SubPC kit. Double-click the **CMD** once.

**Prompts (values are kept locally and NOT exported):**
1. Server-PC **LAN IPv4** (10.x.x.x, 172.16–31.x.x, or 192.168.x.x), from the Minecraft server's network settings.
2. Server-PC **IPv6** address, if present and usable from SubPC (ULA, link-local with required Windows scope index, or global unicast). If genuinely unknown/unavailable, press Enter. This will mark IPv6 **UNVERIFIED**, not PASS. Do not use the SubPC's own IP or `::1`.

After it finishes, upload only `Desktop\Geumyi-Day12-DualStack-Proof\Day12-SubPC-DualStack-YYYYMMDD-HHMMSS.json` to this conversation. The JSON contains port numbers/outcomes, family/scope classification, timestamp, and limits, but no target IP/hostname/PID/credentials/paths.

## What the diagnostic does (no mutations)

- From a physically different Windows PC, tries **three public Java/TCP Velocity control ports** `25565/25566/25567` and **eight private Java/RCON TCP ports** `25570–25573,25575–25577,25579` per supplied address family.
- IPv4 and IPv6 results are **separate**. One public TCP control must be reachable on a family before its eight private negative connection results count as interpretable remote-path evidence.
- If any private port is TCP-connectable from SubPC, the result is `EXPOSURE_SIGNAL_REVIEW` and requires private incident triage; do not change policy automatically or publish credentials.
- If IPv6 is unconfigured/unrouted/no positive public TCP control, its outcome is **INCOMPLETE/UNVERIFIED**, never treated as an IPv6 security PASS.
- Never sends Minecraft login/RCON commands, credentials, game data, HTTP admin API requests, ICMP sweeps, packets to arbitrary ports, UDP, or firewall modifications. Does not stop/restart Paper, Velocity, GSC or Java; does not touch worlds or Golden backups.

## What it cannot prove

This check is **not** proof of kernel-level exclusive bind/OS PID ownership; remote TCP non-reachability may be caused by Windows firewall/routing, and a successful public control covers only the tested path. Bedrock UDP public ingress, IPv6 from other hosts, Internet, Tailscale/overlay interfaces and effective firewall precedence remain separately unproven. It must **not** set `backend_ports_private=PASS`. It is only an independent path-of-exposure result for a *separately approved* compensating-control review.

## Stop conditions and next engineering decision

- **Refuse** if the script is launched on the server PC, cannot read local interface addresses, or receives loopback/public IPv4.
- **Stop** and report if any private port is reachable; do not restart/rebind/disclose secrets to investigate.
- If dual-family public controls succeed and private ports are unreachable, retain `REMOTE_PRIVATE_UNREACHABLE_AT_TESTED_VANTAGE` as a **bounded observation**. Proceed to review VPN/overlay scopes and exact firewall-policy evidence with operator approval before any live firewall changes.
- If one family is unavailable, do not rerun identical previous IPv4-only scanner; classify why IPv6 is unavailable and use a materially different valid attestation method. Do not fabricate IPv6 data or mark 12.10 complete.

## CI and version freeze

The workflow `.github/workflows/day12-subpc-dualstack-kit.yml` packages only these scripts and this runbook. Source/PowerShell parser, zero-network synthetic classification, localhost rejection and ZIP content are checked on **disposable Windows GitHub Actions**. A green CI report is not a green live security report. No production binary update or firewall policy change is authorized by this read-only kit.
