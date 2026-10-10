# Day 12.10 — Real server-PC targeted firewall candidate review

**Capture:** 2026-10-10 04:25:46 KST  
**Private source:** `Day12-Firewall-Target-20261010-042526.json` (retain operator-side, do not upload raw JSON into git)  
**Execution:** `synthetic=false`, `read_only=true`, `result=CAPTURED_FOR_REVIEW`, `mutation_performed=false`, `secrets_exported=false`.

## Grounded host facts

- **Active network categories:** Private, Public. Domain, Private, Public firewall profiles all `enabled=True`, `default_inbound_action=Block`, `allow_inbound_rules=True`.
- **Enabled inbound firewall rules examined:** 268. **Programmatically prefiltered candidates:** 118. **Associated-filter query failures:** 0. No diagnostic error categories.
- **All eight protected TCP Java/RCON ports** — Java `25570, 25571, 25572, 25573` and RCON `25575, 25576, 25577, 25579` — had identical broad candidate sets in the original v1 diagnostic report:
  - 113 `Allow` rule candidates, one `Block` rule candidate, 21 `POSSIBLE_UNKNOWN` candidates, and zero authenticated-bypass/unknown security-rule candidates according to the **collector's coarse metadata**.
  - **40 distinct `Allow` candidates per port** had `program_scope=ANY`, a supported protocol of `TCP` or `Any`, and `remote_address_scope=ANY`. **38/40** had `local_address_scope=ANY`; **2/40** were `RESTRICTED_OR_COMPOSITE_REDACTED`. All 40 have `authentication_scope=NotRequired`; relevant profiles include Private or Any, with some explicitly applying Public.
  - The single `Block` candidate per port was **Public profile**, `TCP`, **`SPECIFIC_REDACTED` program**; the sanitized report cannot show whether it targets any Paper Java instance. It is **not** evidence that the backend ports are blocked.
- **Public Velocity Java** candidates: port `25565`: 114 Allow + 1 Block; `25566`: 114 Allow + 1 Block; `25567`: 113 Allow + 1 Block. A single additional candidate (ordinal **197**) applied to `25565`/`25566` in the sanitized report and was absent from `25567`; no rule identity can be inferred from ordinal alone. The known separate LAN public 3/3 control is historical, not a 04:25 live test.

## Collector over-count — identified from the original uploaded JSON, without a new host scan

The first `ProtocolScope` classifier treated **15 unambiguously non-TCP** rules as possible TCP candidates: **12 ICMPv6, one ICMPv4, one IP protocol 41 (IPv6 encapsulation), and one protocol 2 (IGMP)**. It intentionally flagged unknown protocols fail-closed, but this was overinclusive for protocols that definitively are not TCP. The source classifier now excludes those specific known non-TCP protocols, while retaining truly unknown protocol values for review.

**Offline-adjusted per-port counts from this one 04:25 JSON, NOT a new 04:25 host scan:**

| Port class | Former candidate Allow | Adjusted Allow | Adjusted Block | Remaining ambiguous |
|---|---:|---:|---:|---:|
| Each private Java/RCON TCP port (8) | 113 | **98** | **1** | **6** |
| Velocity public TCP `25565`, `25566` | 114 | **99** | **1** | **6** |
| Velocity public TCP `25567` | 113 | **98** | **1** | **6** |

The **40 broad Any-program Allow candidates per private port remain** after this correction. These numbers are *potentially relevant rule candidates*, not the count of actual TCP listening sockets, external access grants, or exploitable exposures. Rules can apply to specific executable paths, services, interfaces, source address scopes and networks; those specifics were deliberately not exported. The original 118 prefiltered candidate-rule count should not be compared numerically to per-port counts, which repeat many of the same firewall rules.

## Security interpretation

1. **Do not infer that 98 rules effectively allow remote access to backend TCP.** Many rules target other programs or services. The report lacks application identity correlation, effective WFP rule precedence, exact address families, profile/interface binding, group-policy conflicts, IPsec and VPN/Tailscale path details.
2. **Do not infer protection from a single Block candidate.** The sole per-port Block has a specific program, not verified as Minecraft, and matches only Public profile. A generic default inbound Block is important but other Allow candidates may override the default for matching traffic.
3. The **40 Any-program broad Allow candidates** require further classification and policy minimization review before claiming robust defense against accidental backend misbinding. Previously observed LAN private-port **0/8 not reachable** is a *single-path negative probe*, not global IPv4/IPv6 / VPN / Internet security attestation.
4. The mandatory canonical `backend_ports_private` remains **FAIL**: no simultaneous owner-attributed IPv4+IPv6 loopback LISTEN evidence. This firewall metadata cannot replace it or justify Day 12.13 Stable.
5. **No live config changes approved.** Do not disable unidentified Allow rules, add a broad firewall block, enable WFP auditing or restart production just to produce logs. Preserve public Velocity (TCP 25565–25567), Bedrock (UDP 19132–19134), locally routed Paper/RCON, GSCM/management and existing Golden backups. Use a disposable staging scenario, rule backup, and explicit operator approval for any future protection-policy change.

## Engineering follow-up

- Fixed `tools/day12/Day12_Phase10_Firewall_Target_Rules_READ_ONLY.ps1` to distinguish explicitly known non-TCP protocols from genuine unknowns; its CI synthetic fixture asserts exclusions. **The original operator JSON is retained as original evidence and was not rewritten.** Windows Day 12 Safety CI run `37980375757` subsequently **PASS** for the corrected script on source commit `ecd6d7d98`; this is a synthetic classifier result, not a fresh production policy verdict.
- Prepare a **read-only, target-executable-scoped** rule review design with stricter private classifier: compare actual active Paper Java executable identity to rule program identity *only on the local server*, expose coarse `PROGRAM_MATCH`/`PROGRAM_OTHER`/`PROGRAM_ANY`/`UNKNOWN` classification without leaking paths/PIDs. Validate from Windows synthetic fixtures first; avoid making users repeat unchanged host probes.
- A compensating firewall-control release policy, if proposed, is **distinct** from proving canonical bind isolation; must be independently threat-modeled, explicitly approved and testable across LAN/overlay/IPv6 without GSC lockout.
- Until then, proceed only with repository-side preparations. Strict gate still **FAIL**; 12.11 release-grade E2E, 12.12 real soak and 12.13 Stable are **PENDING/BLOCKED**.

See [compensating controls review](DAY12-PHASE10-COMPENSATING-CONTROLS-REVIEW.md) and [latest security decision packet](DAY12-PHASE10-SECURITY-DECISION-PACKET.md).
