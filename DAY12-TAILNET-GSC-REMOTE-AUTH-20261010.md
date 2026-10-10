# Day 12 — SubPC Tailscale GSC Host API unauthorized HTTP check

**Basis:** real 2026-10-10 09:33:48 KST SubPC Tailscale IPv4+IPv6 report confirmed 4/4 public TCP controls including GSC API **8787** and **0/8** private Paper Java/RCON backend connections on each family. Other physical LAN IPv4+IPv6 evidence is already captured and must NOT be repeated.

The management API TCP port **is intentionally reachable** for authorized administration through Tailscale. Source `GSC/ServerCenter/cmd/host/v42_mobile.go` limits trusted remote address ranges, and `v41_control.go` requires credentials for protected routes. `main.go` `/api/health` is intentionally public minimal health/version JSON. The route `/api/v1/pairing/claim` intentionally supports a separate pairing flow. Static source and CI do not prove the running server still enforces remote authorization.

## Single independent runtime task — after focused Windows CI PASS

On **SubPC only**, extract the focused ZIP and double-click `Day12_SubPC_Tailnet_GSC_Unauth_HTTP_READ_ONLY.cmd`. Enter the **SERVER PC** Tailscale IPv4 and optional IPv6 (not a LAN or SubPC address). No credentials, API tokens or pairing codes are requested.

The script performs `GET /api/health` to confirm GSC Host generation 4 service identity, then unauthenticated `GET` to four protected routes (info, snapshot, devices, settings) on each selected Tailscale family. It does not read/export response bodies, usernames, host IPs, headers, paths from the PC, or secrets; the JSON contains only endpoint names, HTTP status codes, synthetic=false and verdicts. Proxy use and HTTP auto-redirects are disabled.

**Important limitation:** although no state-changing endpoint, Java command, update, config, firewall, backup or world action is invoked, unsuccessful API requests normally append **ordinary unauthorized-access audit log entries** on the GSC server. Thus this is a non-mutating **client request**, not a zero-writes-on-server operation. Expect up to eight routine audit entries, which is normal for a security test.

Evidence classification:
- All four protected routes return `401` and Host identity is confirmed: `GSC_REMOTE_API_REQUIRES_AUTH_TESTED_PATH` for that family.
- An unexpected `2xx` or `3xx` protected-route response: `POTENTIAL_UNAUTHENTICATED_API_EXPOSURE`. Do NOT send credentials, repeat, or change firewall; investigate.
- `403` can mean network guard or mobile-disabled rather than route-level authorization: `DENIED_BUT_AUTH_VS_NETWORK_GATE_NOT_FULLY_PROVEN`.
- Missing Host identity, network errors, timeout or mixed other statuses: `INCONCLUSIVE`, never PASSED.

Output `Desktop\Geumyi-Day12-Tailnet-Auth\Day12-Tailnet-Auth-*.json`; upload that file here. If actual Host is down or service identity unverifiable, stop; avoid repeated probes and do not infer missing authentication.

**Canonical 12.10 native OWNER_PID/IPv4+IPv6 kernel bind gate remains FAIL even after real API HTTP-401 evidence.** The separate 12.5 ACL/firewall policy review, full 12.11/12.12 and Stable also remain unresolved. No GSC Host production update required.
