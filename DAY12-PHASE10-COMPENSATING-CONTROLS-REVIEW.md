# Day 12.10 — Separate compensating network controls: review only

**Status: DESIGN / NOT APPROVED / NOT DEPLOYED / canonical backend_ports_private still FAIL.**

Prepared after the real 2026-10-10 04:13 KST WFP v2 server-PC report showed `NO_EVIDENCE` (0 matching 5154/5158 records, 11 Java processes enumerated), after earlier repeated Windows TCP listener inventories disagreed with real localhost service connections.

## Goals, boundaries and explicit non-goals

The original strict requirement is **actual backend Java/RCON exclusive loopback binding** on every online backend, including IPv4/IPv6, with positive process ownership evidence. This remains the existing canonical validation requirement; it is not fulfilled or silently replaced by firewall rules or negative probes.

**Compensating network controls** are a *different* security claim: accidental misbinding must remain unreachable from remote networks because a verified effective firewall policy blocks private backends while preserving intended public Velocity/Geyser entry. It does **not** prove the sockets themselves are exclusively loopback-bound. Adopting that as release-grade requires separate operator approval, explicit residual-risk acceptance, test design, review and a separately versioned verifier. Do not edit the existing `backend_ports_private` gate to PASS.

No changes to Windows Firewall, auditpol, ACLs, server processes, `server.properties`, RCON tokens, proxy forwarding secrets, startup tasks, network routes, Tailscale ACLs, Java world data, protected Golden backups or update/restore state are authorized by this review.

## Exact intended network separation

| Class | Protocol | Ports | Intended source/destination | Review objective |
|---|---|---|---|---|
| Velocity public aliases | TCP | 25565, 25566, 25567 | Remote clients → Velocity (Lobby first) | MUST keep working |
| Bedrock public aliases | UDP | 19132, 19133, 19134 | Bedrock clients → Geyser routing (Lobby first) | MUST keep working |
| Java backend Paper | TCP | 25570, 25571, 25572, 25573 | Loopback/authorized local proxy only | MUST NOT be remotely reachable |
| RCON management | TCP | 25575, 25576, 25577, 25579 | Local GSC management only | MUST NOT be remotely reachable |
| GSC management API | TCP | 8787 (seen previously) | Authenticated administrator clients under specifically reviewed access policy | Separate security review; DO NOT lump into game proxy |

The table reflects the intended topology `FINAL-NETWORK-TOPOLOGY.json`, not a fresh guarantee of currently bound endpoints or all dynamic listeners.

## Preconditions before proposing any firewall policy change

1. Inventory the effective **ActiveStore inbound rules**, all active profiles (Domain/Private/Public) and remote/interface filters; review both narrow public rules and the prior **33 UNCLASSIFIED broad Any-program/Any-port** candidate rules. Rule names are NOT enough to identify safe removals; previous Day12.5 report also flagged **15 higher-review** public-profile candidates.
2. Determine actual GSC Host, Java, Velocity, Geyser, VPN/overlay and remote-management service identities **privately**, without exporting full command lines, IP addresses, access tokens, passwords or paths.
3. Review local proxy-to-backend connection path, loopback exception behavior, IPv4-mapped IPv6 and IPv6 policies; do NOT presume a proposed block rule will leave 127.0.0.1 / ::1 traffic untouched. All filtering changes must be independently tested in a disposable environment before any host-wide application.
4. Record current relevant rules and restore instructions in a protected operator-side backup; verify Golden 4/4 and known-good cache without recreating protected archives, no active update job, no player sessions and an approved maintenance window.
5. Design narrowly scoped **explicit denies** for remote access to the eight backend ports. Do not produce or run broad “block all Java” or “disable all firewall” commands. The rule ownership, precedence over broad allows, local interface effects, address family and conflicts with GSC must be confirmed first.
6. Rehearse with disposable/staging Paper+Velocity first; prove that public Java and Bedrock entries remain usable, proxy-to-each-backend and GSC-to-RCON localhost still work, while distinct remote LAN, overlay/VPN and IPv6 vantage points cannot reach the private ports.
7. Capture signed or independently verifiable pre/post effective-policy evidence with explicit source time and scope; negative remote probes need successful positive public control from the **same** path. Any outside-reachable private port is a hard failure and stop condition.

## 2026-10-10 — per-port ActiveStore rule candidate classifier, PREVIEW ONLY

- Source: `tools/day12/Day12_Phase10_Firewall_Target_Rules_READ_ONLY.ps1`, synthetic Windows CI fixture in `.github/workflows/day12-safety-ci.yml`. This is *not* a deployed policy or verified private bind.
- It reviews only enabled inbound rules in Windows ActiveStore, retaining **both Allow and Block** candidates relevant to TCP Java/RCON ports **25570/71/72/73, 25575/76/77/79**. The three public Velocity TCP **25565/66/67** serve as read-only comparison. Bedrock public UDP **19132/33/34** is preserved by policy and is not modified or inferred from the TCP-only check.
- Profiles and defaults are collected; candidate summaries include protocol, exact/range/wildcard/dynamic local-port match, program specificity, local/remote-address scope, interface/service scope, authentication and block override, with all raw IPs, application paths, interface aliases and rule names omitted.
- Named/dynamic port keywords, unrecognized profiles/protocols and missing filter data are classified as **unknown** rather than dropped as safe. Filter failures mark the overall collection `CHECK_REQUIRED`. Each target remains **`CANDIDATE_REVIEW_ONLY`**, never PASS, including where a Block candidate appears: a matching allow/authenticated bypass, other OS firewall layers, VPN routing or IPv6 scope may require separate analysis.
- The tool does **not** emulate the Windows Filtering Platform classifier, claim effective security or touch any running service/port/world/config; it does not run `New-NetFirewallRule`, `Set-NetFirewallRule`, `auditpol`, or a TCP connection. An observer of these results cannot infer that all possible remote addresses are denied.
- Continue reviewing the known **38** broad inbound Allow candidates, including **33** unclassified and **15** higher-review profile candidates from 12.5. That prior count is historical; avoid calling it a freshly verified count.
- This check, when CI-verified, could provide genuinely distinct **effective-policy metadata** compared to the previous name-only heuristic, but does not close strict `backend_ports_private` or authorize changing host firewall rules. No administrator intervention is requested until CI/kit verification completes.

## Disposable runner test result — 2026-10-10

- One GitHub Windows **disposable** runner test **PASS** in Actions run `37982653272`: a temporary nonloopback IPv4 local-address-scoped inbound TCP Block rule on an ephemeral port was created, locally read back and deleted in `finally`; its separate `127.0.0.1` listener remained connectable before and after. The original Minecraft host was **not** touched.
- This limited result **does not verify remote filtering efficacy**, IPv6/overlay/DHCP changes, GSC/Velocity/Paper/RCON behavior, or current backend bind ownership. The mandatory canonical gate remains **FAIL**.
- A second network vantage point, IPv4/IPv6 comparisons and application-aware/rollback proof are prerequisites to seeking approval for any production firewall change. Preserve current 36 broad candidate rules until identities and dependencies are privately resolved.
- [CI outcome and exact limitations](DAY12-PHASE10-DISPOSABLE-FIREWALL-RESULT-20261010.md).

## Approval and rollback gate

**Approval required before modifying any live security policy**. Present the actual exact rule changes and expected scope, dependencies, possible lockout/service impact, and a reversible rollback procedure to the operator. Require a separate **yes** to deploying the narrowly scoped rules. On any failed connectivity, backend health or unexpected client regression, undo only the approved new rules using the saved previous state, restore expected public entry and local GSC/RCON operations, and retain the Golden backups. A production restore is never the default rollback for a firewall-only change.

Do not proceed if previously unidentified broad Allow rules or IPv6/overlay paths remain unknown; document `CHECK_REQUIRED` rather than using a pass-by-default policy.

## Decision status

| Criterion | Status |
|---|---|
| Prior real host Java `server-ip` and app startup loopback evidence | HISTORICAL, partial |
| Prior 0/8 private-port reachability from second LAN PC | PARTIAL negative vantage |
| Current simultaneous IPv4+IPv6 bind + owner proof | MISSING |
| Existing WFP Security 5154/5158 history | NO_EVIDENCE (04:13 KST) |
| Firewall broad-Allow identity review | INCOMPLETE (33 unclassified) |
| Overlay/VPN/IPv6 policy and outside-host validation | INCOMPLETE |
| Separate compensating policy authorization | NOT REQUESTED / NOT GRANTED |
| Canonical `backend_ports_private` | FAIL, UNCHANGED |
| Day12.13 stable / cleanup | BLOCKED |

**Preferred next engineering work without host interaction:** source-level design of an effective-rule report that would resolve policy precedence/address scope on Windows, with synthetic fixture for wildcard/broad Allows and IPv6/overlay unknowns. This is *preparation only*, not a request to change the actual firewall.

## Source pointers

- [Day12.5 operator-reported firewall/ACL scope](DAY12-PHASE5-SECURITY-REVIEW.md)
- [Day12.10 bind discrepancy and preserved risk gate](DAY12-PHASE10-BIND-DECISION-REPORT.md)
- [Canonical topology](FINAL-NETWORK-TOPOLOGY.json)
- [Security decision packet](DAY12-PHASE10-SECURITY-DECISION-PACKET.md)
- [WFP v2 audit evidence review](DAY12-PHASE10-WFP-READONLY-PLAN.md)
- [Microsoft WFP Audit Filtering Platform Connection](https://learn.microsoft.com/ko-kr/previous-versions/windows/it-pro/windows-10/security/threat-protection/auditing/audit-filtering-platform-connection)


## 2026-10-10 09:26:20 KST — actual IPv6 link-local + validated SubPC Wi-Fi scope: remote private endpoints 0/8

- Real uploaded report `Day12-IPv6-Scope-20261010-092620.json` (private evidence, not committed) declares `phase=12.10-subpc-ipv6-scope-only`, `synthetic=false`, `read_only=true`, `mutation_performed=false` and `target_scope=LINK_LOCAL`. The previous `fe80::...%15` **server-PC zone index** had caused `INVALID_OR_DISCONNECTED_SUBPC_INTERFACE_SCOPE` in the first v2 run. Corrected Windows CI ([`38008744859`](https://github.com/geumyi22/Geumyi-Minecraft-System/actions/runs/38008744859), SUCCESS) discarded remote-zone provenance, and the operator explicitly selected connected **SubPC Wi-Fi interface 3** rather than Tailscale interface 24. Do not repeat this valid test.
- With the actual SubPC interface index, **all three public Java Velocity IPv6 TCP controls 25565/25566/25567 connected**, **all eight private Java/RCON IPv6 TCP ports timed out**. `public_control_connected=3`, `private_connected=0`, `result=REMOTE_IPV6_PRIVATE_UNREACHABLE_TESTED_PATH_ONLY`, `ipv4_probes=0`. The ICMP probe was `NO_ICMP_REPLY_OR_BLOCKED`; it does not contradict **successful TCP** public controls and is not a security PASS by itself.
- Paired with real 09:11 SubPC **IPv4 3/3 public and 0/8 private**, this gives meaningful independent **both-family LAN-exposure separation evidence** from the **same separate Windows PC**. Explicit labels: **IPv4 LAN path = TESTED_UNREACHABLE; IPv6 link-local Wi-Fi path = TESTED_UNREACHABLE**. It does **not** establish all IP paths, Internet or Tailscale/VPN routing, the effective WFP/ActiveStore policy, or current exclusive OS Java/RCON bind/PID ownership.
- Canonical `backend_ports_private=FAIL` and Day12.10 OPEN, 12.5 runtime security review partial, full 12.11 live E2E, 12.12 soak and Stable/maintenance blocked; do not set any release live gate PASS or remove backup protection. **No further IPv4/IPv6 Wi-Fi LAN remote port probe is warranted** without an actual environment change.
- Separate new remaining question: user screenshot shows active Tailscale adapter and server has tailnet addresses. An **overlay vantage** is materially different from validated physical LAN, and potential Tailscale port access must be separately assessed if used. Do not silently count LAN v4/v6 as Tailscale policy evidence. Plan a narrowly scoped, no-write SubPC-to-known-server-tailnet remote TCP positive-control check, not another identical LAN scan, with fail-closed absent overlay control; any Tailscale route check still does not directly prove OS bind+PID.
