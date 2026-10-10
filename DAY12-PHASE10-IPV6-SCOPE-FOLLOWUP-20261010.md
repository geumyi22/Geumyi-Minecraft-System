# Day 12.10 — IPv6-only scoped-path follow-up (no duplicate IPv4)

## Actual operator evidence that led to this tool

2026-10-10 09:11:48 KST **SubPC real read-only** file `Day12-SubPC-DualStack-20261010-091148.json` was reviewed privately. No raw IPs were exported:
- IPv4 RFC1918 tested path: **3/3 Velocity public TCP positive controls CONNECTED** and **0/8 private Java/RCON ports connected** (all 8 TIMEOUT); therefore `REMOTE_PRIVATE_UNREACHABLE_AT_TESTED_VANTAGE` for that IPv4 LAN path.
- IPv6 target was **link-local**. The three TCP positive controls and eight private ports each returned `REJECTED_OR_NETWORK_ERROR`. Therefore `INCONCLUSIVE_NO_PUBLIC_CONTROL`; **IPv6 security remains UNVERIFIED**, NOT safe.
- The v1 report did not record whether a valid **SubPC adapter %scope** was used and did not discriminate local link-scoping/routing failures from connection refusal. This is an **information gap**, not proof the previous IPv6 error was caused by scope. The previous IPv4 result stays preserved and shall NOT be rerun.
- Windows documents [link-local scope IDs](https://learn.microsoft.com/en-us/windows/win32/winsock/link-local-and-site-local-addresses-2) using the **originating local computer's interface index**, not an index copied from another PC. Remote target `fe80::...` may need `%index` resolution on multi-interface PCs.

## New deliberately bounded read-only operator step

Run on **SubPC only**, never server PC. Focused CI ZIP contains:
- `Day12_Phase10_SubPC_IPv6_Scope_Only_READ_ONLY.cmd`
- `Day12_Phase10_SubPC_IPv6_Scope_Only_READ_ONLY.ps1`
- this guide, SHA256 manifest.

Double-click the CMD, enter the **same server-PC IPv6 target** that was used in the previous report. For a link-local `fe80::` target, the tool discovers **SubPC active link-local IPv6 interface indices** (does not export aliases or addresses). If there is exactly one, it assigns the scope automatically; if multiple, it offers the numeric indices and asks the operator to pick the **SubPC's actual LAN interface**, not the server's interface. **Corrected after the 09:20 real screenshot:** The previous version rejected an input `fe80::…%15` because `%15` was not an active interface index on the SubPC (`INVALID_OR_DISCONNECTED_SUBPC_INTERFACE_SCOPE`, exit 1). A pasted `%index` can legitimately come from the **server PC**, so rejecting it was a tooling defect, not evidence of a server fault. The corrected tool **always ignores any pasted link-local `%index`** and derives the zone from the SubPC's currently connected IPv6 LAN interface; with one active interface it chooses automatically, with several it lists the SubPC's interface numbers and local Ethernet/Wi-Fi names and asks for the correct SubPC adapter. Even an accidentally matching number is not trusted without local selection. Invalid addresses or unresolved local scope fail closed without network probes.

It uses an IPv6 ICMP echo **solely for route context** and sends only the fixed 3 Velocity TCP positive controls plus 8 Java/RCON private-port TCP connect attempts **via IPv6**. No IPv4, credential, Minecraft login, RCON payload, GSC API, UDP or changing any firewall/service/OS/world/backup settings.

Output: `Desktop\Geumyi-Day12-IPv6-Scope\Day12-IPv6-Scope-*.json`. Upload that JSON, not raw addresses. The new report distinguishes:
- `REMOTE_IPV6_PRIVATE_PORT_REACHABLE_REVIEW`: at least one private IPv6 TCP port was reachable; potential network exposure signal
- `REMOTE_IPV6_PRIVATE_UNREACHABLE_TESTED_PATH_ONLY`: one or more public IPv6 TCP controls connected, private ports did not
- `IPV6_PATH_REACHABLE_BUT_NO_TCP_CONTROL`: ICMP reply received, but none of three public Velocity TCP ports accepted IPv6; no positive TCP control, **still inconclusive**
- `IPV6_PATH_OR_PUBLIC_TCP_UNVERIFIED`: neither ICMP reply nor any public TCP control, **still inconclusive**

**Absolutely never upgrade the canonical `backend_ports_private` gate from this result.** IPv6 from SubPC does not establish current exclusive listener binding/owner, all Internet/VPN/overlay paths, real Java/Bedrock login, or effective Windows firewall/WFP policy. If there is still no public IPv6 positive control after scope correction, **do not keep repeating remote probes**; identify whether Velocity deliberately exposes only IPv4 and choose separate scope-appropriate attestation or explicitly approved compensating security controls.

The Windows CI's `-Synthetic` mode never sends any network packets and only tests address-scope and fail-closed classification. Passing CI is **not** actual live IPv6 proof.
