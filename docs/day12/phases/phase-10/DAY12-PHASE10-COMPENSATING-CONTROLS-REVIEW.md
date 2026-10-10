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

- [Day12.5 operator-reported firewall/ACL scope](../phase-05/DAY12-PHASE5-SECURITY-REVIEW.md)
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


## 2026-10-10 09:33:48 KST — real SubPC Tailscale dual-stack path: public 4/4, backend 0/8, BOTH families

- Received actual private operator report `Day12-Tailnet-20261010-093348.json`, explicitly `synthetic=false`, `read_only=true`, `mutation_performed=false`, `secrets_exported=false`. Verified `ipv4.status` and `ipv6.status` both `TAILNET_PRIVATE_BACKEND_UNREACHABLE_TESTED_PATH_ONLY`, report `OVERLAY_BOTH_FAMILIES_BOUNDED_NEGATIVE`. The Tailscale IPv4 **100.64/10** and Tailscale IPv6 **fd7a:115c:a1e0::/48** paths each had 4/4 control TCP **CONNECTED** (Velocity 25565–25567 and GSC API 8787) and 0/8 private Java/RCON connections (all TIMEOUT).
- Combined with 09:11 IPv4 LAN (3/3 public, 0/8 private) and 09:26 IPv6 link-local LAN (3/3 public, 0/8 private), **all four actually tested remote-family/vantage paths** yielded positive TCP controls and zero private backend connections. No additional probe of those same four paths is justified now. The checks never used RCON secrets or service-modifying requests.
- **Attention: the GSC management TCP port 8787 is reachable over Tailscale IPv4 AND IPv6**. This is expected by Host source `v42_mobile.go` (allow remote LAN/tailnet with `MobileEnabled`) and `main.go` (`0.0.0.0:<port>` listener); it does **not** mean API information or actions are accessible without authentication. Source `v41_control.go authenticateRequest` accepts remote credentials, reserves `AllowLoopbackNoAuth` for actual loopback RemoteAddr; `requireAuth` guards status/management/most v1/v4 endpoints. `/api/health` is intentionally public minimal JSON, and `/api/v1/pairing/claim` is a purpose-built controlled pairing route; these must be reviewed separately, not described falsely as all endpoints requiring credentials.
- A targeted disposable source regression was added at `GSC/ServerCenter/cmd/host/tailnet_auth_regression_test.go` (commit `96293a13929fa973805c827e0ff5f5bed9538088`): remote CGNAT IPv4 and fd7a IPv6, missing/incorrect token, forged loopback/actor headers must return 401 for selected status/control routes; disabled mobile access returns 403. **Go test/CI does not prove actual running Host remote HTTP authorization**. Do not call a TCP connect a GSCM credential test.
- Real Windows kernel listener bind addresses/PID remain **unattested** after prior OS provider discrepancies; absence of TCP access from one SubPC does not exclude firewall/ACL differences for other tailnet peers or Internet paths. **Original `backend_ports_private=FAIL` unchanged, full 12.5 runtime policy review OPEN, final 12.11/12.12/12.13 and Stable/maintenance BLOCKED.** No production reboot/firewall/service changes are authorized or performed.
- Recommended next **distinct** action after Go CI: verify existing Host API unauthorized response with minimal no-credential requests on the *actual separate SubPC tailnet IPv4+IPv6 path* if requested/authorized; such requests can create normal Host audit entries, so label them observable application GET, not zero server writes. Alternatively, stop testing and record static source + unverified real auth. Do not repeat LAN/overlay TCP scans.


## 2026-10-10 09:41:32 KST — actual GSC Tailscale unauthenticated API GETs DENIED on IPv4 AND IPv6

- The operator supplied real sanitized `Day12-Tailnet-Auth-20261010-094132.json` privately: `synthetic=false`, `phase=12.10-tailnet-api-auth`, `result=TAILNET_BOTH_FAMILIES_AUTH_DENIED`; no production config changes. Confirmed GSC Host service identity on both Tailscale IPv4 and fd7a IPv6.
- Each family returned HTTP **401 for ALL FOUR protected GET routes** (`/api/v1/info`, `/api/v1/snapshot`, `/api/v1/devices`, `/api/settings`); **8/8 DENIED**, 0 successful protected requests, 0 HTTP 403. This is **real** present-time unauthenticated rejection for exactly these paths and this SubPC tailnet vantage, not merely CI or TCP reachability.
- One family independent path matrix at test time: ordinary LAN IPv4 3/3 public TCP controls, protected backend 0/8; ordinary LAN link-local IPv6 3/3 public, protected 0/8; Tailscale IPv4 4/4 public/GSC controls, protected 0/8; Tailscale IPv6 4/4 public/GSC controls, protected 0/8. These four pathways have now been checked with positive controls — **do not repeat** without a changed configuration/hypothesis.
- Host authorization regression [System CI `38009749783`](https://github.com/geumyi22/Geumyi-Minecraft-System/actions/runs/38009749783) **SUCCESS**. Targeted Windows zero-credential GET kit [`38009959838`](https://github.com/geumyi22/Geumyi-Minecraft-System/actions/runs/38009959838) **SUCCESS**. The real GETs may create up to 8 normal denied-request Host audit entries; this is an expected minor server-side audit write, not a security bypass.
- **Do not infer** Java/RCON exclusive socket bind or PID owner, firewall/WFP effective policy for all interfaces/other tailnet clients, UDP Bedrock login, or full 12.5 ACL correctness. `backend_ports_private=FAIL` stays, original Day12.10 strict gate OPEN; 12.11 E2E, 12.12 soak, Day12.13 Stable + maintenance still BLOCKED.
- **Next engineering focus: not another SubPC connectivity test.** Evaluate the existing `Day12_Phase10_Firewall_Target_Rules_READ_ONLY.ps1` and 12.5 ActiveStore/ACL evidence for a narrowly scoped compensating-policy decision, while preserving canonical owner gate; OR prepare a genuinely independent kernel attribution approach requiring operator-approved live investigation. Any actual security-policy relaxation, firewall changes or Stable bypass needs separate explicit operator consent. No unattended production mutations.


## 2026-10-10 — existing 04:25 sanitized ActiveStore snapshot, NEW offline TCP-only rule triage (no re-scan)

- Recovered and programmatically analyzed the already provided real **`Day12-Firewall-Target-20261010-042526.json`**. Source `synthetic=false`, `result=CAPTURED_FOR_REVIEW`, `rule_filter_read_failures=0`, `enabled_inbound_rules_examined=268`, `rule_candidates_matched=118`, active network profiles `Private` and `Public`, default inbound `Block` on all three firewall profiles. The snapshot is **historical as of 04:25 KST**, not a fresh 09:41 policy certification.
- The original earlier collector reported **113 Allow / 1 Block and 21 ambiguous** per backend port because it included protocol 41 and ICMP candidate rows. **Offline TCP-specific filtering** (TCP/6/Any only, de-duplicated by snapshot-local ordinal across all 8 ports) yields **99 distinct** relevant candidate rules: **98 Allow and 1 Block**. Of 99, **6 remain `POSSIBLE_UNKNOWN`**; **40 Allow candidates have program ANY plus remote ANY**, and **38 of those** have ALL FIVE recorded coarse scope fields (`program`, local/remote address, interface, service) = `ANY`. Those 38 are **broad *candidates***, not verified effective firewall permissions: other filter conditions/OS precedence and process binding may still restrict them.
- The solitary Block candidate is scoped to `Public` and `SPECIFIC_REDACTED` program: it **cannot** alone substantiate protection of all four Paper/RCON instances on all Private/Public/Tailscale profiles. Likewise default-inbound Block does **not** establish that 40 broad Allow candidates are harmless.
- Source-only analysis and synthetic regression: `tools/day12/review_day12_firewall_candidates_offline.py`, `test_review_day12_firewall_candidates_offline.py`; [pure offline CI `38010447589`](https://github.com/geumyi22/Geumyi-Minecraft-System/actions/runs/38010447589) **SUCCESS**. This deliberately omits the private 1.7MB firewall evidence file from GitHub and does **not** probe or change production; snapshot ordinals are for review only and **never a Windows firewall rule ID**.
- The new *real* four-vantage TCP and 8/8 unauthenticated GSC 401 evidence supports **current tested-path isolation**, but because the historical ActiveStore snapshot has many potentially permissive Allow rules **a compensating firewall rule case cannot be auto-approved**. Current kernel LISTEN/PID and full ACL policy evidence remain missing. No unreviewed block/delete/new allow policy should be applied. **`backend_ports_private` stays FAIL and Stable remains BLOCKED.**
- Engineering decision: **stop all repeated remote probing**. Next meaningful live activity must be either an independently justified, operator-approved current OS process/socket attribution method (not GetExtendedTcpTable/GetTcpTable2/netstat/NetTCPConnection again), or explicit risk-accepted and independently verified compensating policy with precise rollback/real Windows ACL/ActiveStore precedence review. Do not silently edit `FINAL-RELEASE-GATES.json`.
