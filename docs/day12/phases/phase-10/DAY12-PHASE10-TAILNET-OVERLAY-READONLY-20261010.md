# Day 12.10 — Tailscale overlay independent-path check, SubPC READ ONLY

**Status: prepare + CI verify first. Never auto-change Tailscale ACLs, firewall or GSC.**

## Evidence already settled; avoid duplicate tests

Actual 2026-10-10 09:11 and 09:26 **SubPC real physical LAN** reports: Velocity TCP positive controls **3/3 connected** on both IPv4 (RFC1918) and IPv6 (link-local Wi-Fi); **0/8 private Java/RCON ports connected** for both IP families. This is strong *bounded LAN* isolation evidence. Do **not** redo either LAN test unless the environment changes.

The server screenshot also showed a **Tailscale** adapter and tailnet IPv4/IPv6 addresses. A tailnet/vpn interface is a **different remote ingress path** and cannot be inferred safe from ordinary Ethernet/Wi-Fi LAN results.

## Next test — once the focused Windows CI run has passed

- Download the focused `day12-subpc-tailnet-readonly-kit` ZIP, extract onto the **SubPC**, and double-click `Day12_Phase10_SubPC_Tailnet_Exposure_READ_ONLY.cmd`.
- Enter the **SERVER-PC Tailscale IPv4** from the server computer's `ipconfig` under Tailscale (format `100.x.y.z` within `100.64.0.0/10`), **not** its `192.168.x.x` LAN address, and not the SubPC's own Tailscale address.
- Optionally enter the **SERVER-PC Tailscale IPv6** (`fd7a:115c:a1e0::...`). If unknown, press Enter: IPv6 tailnet scope is **UNVERIFIED**, never PASS.
- Upload only the generated `Desktop\Geumyi-Day12-Tailnet-Proof\Day12-Tailnet-*.json` here. Raw addresses, credentials and hostnames are never written into the JSON.

The tool refuses to run if GSC Host service is installed, if there is no single active local Tailscale adapter, or if the target is an own SubPC tailnet address. Strictly fixed TCP probes are: **25565/25566/25567 public Velocity**, **8787 GSC management API listener as a TCP positive-control only (no HTTP request/auth)**, **25570–25573/25575–25577/25579 private Java/RCON**. There are no connection payloads, port sweeps, game joins, updates, stop/start, firewall or ACL changes. The tool never attempts the already-proven ordinary LAN addresses.

## Decision rules and operator safety

- Any reachable private endpoint is `TAILNET_PRIVATE_BACKEND_REACHABLE_REVIEW`; capture and review **privately**. This is tailnet exposure to a connected authorized node, not proof of public-Internet exposure.
- With **at least one** remote tailnet TCP positive control connected and **zero** private ports connected, report `TAILNET_PRIVATE_BACKEND_UNREACHABLE_TESTED_PATH_ONLY` — only for that SubPC's tailnet policy and family.
- Without a TCP positive control, the result is `TAILNET_PATH_INCONCLUSIVE_NO_TCP_CONTROL`. Do **not** equate no traffic with safe isolation. Tailscale status, ping and firewall policy would require a separately scoped analysis.
- A negative result does not establish actual Windows socket owner/bind, different tailnet peers' ACL access, dynamic ACL changes, exit nodes, exit subnet routes, internet ingress or local service PID.
- **Strict original `backend_ports_private` remains FAIL** until real IPv4+IPv6 socket owner/bind proof is found or a separately reviewed and explicitly accepted compensating-control policy is adopted. No Stable release or maintenance transition is approved by this overlay scan alone.

GitHub Actions synth only validates address guards, non-mutating program source, ZIP membership and bounded fail-closed classification; **it does not simulate real tailnet policy**.
