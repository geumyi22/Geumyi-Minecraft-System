# Day 12.10 — real Java-to-firewall application identity result (2026-10-10 04:38 KST)

**Private input:** `Day12-Java-Rule-Match-20261010-043824.json` (not committed).  
**Companion previous report:** `Day12-Firewall-Target-20261010-042526.json` (not committed).  
**Operator host execution:** Real, read-only; `synthetic=false`, `result=CAPTURED_FOR_REVIEW`, `mutation_performed=false`, `secrets_exported=false`. No firewall edits, process restarts, secrets, world or backup changes.

## Evidence integrity and key conclusions

| Observed attribute | 04:38 server-PC report |
|---|---|
| Running Java/javaw instances enumerated | **11** |
| Java executable paths acquired | **11/11**, inventory complete |
| Distinct Java executable images | **3** |
| Enabled inbound ActiveStore rules examined | **268** |
| Application/port filter failures | **0** |
| Active profile categories | **Private, Public** |
| Mandatory runtime `backend_ports_private` | **UNCHANGED_FAIL** |

Every one of the four Paper Java target TCP ports (`25570/25571/25572/25573`) and four RCON target TCP ports (`25575/25576/25577/25579`) produced the **same per-port classification**:

| Per-private-port candidate class | Allow count |
|---|---:|
| `ALL_PROGRAMS` | **40** |
| `MATCHES_RUNNING_JAVA_EXE` | **0** |
| `NO_RUNNING_JAVA_EXE_MATCH` | **56** |
| `SPECIAL_SYSTEM_SCOPE` | **2** |
| `PROGRAM_UNRESOLVED` | **0** |
| `JAVA_IMAGE_INVENTORY_INCOMPLETE` | **0** |
| Total Allow candidates | **98** |
| Separate Block candidate | **1** (program path **does not match** a currently observed Java image) |
| Unknown protocol/port/profile scope (within candidate rows above) | **6** |

The public Velocity Java TCP controls (`25565/25566/25567`) show 41, 41 and 40 `ALL_PROGRAMS` Allow candidates, respectively, with zero rules matching running Java images, 56 other-image, two System, one non-Java Block, and six unknown-scope candidates for each.

**Interpretation:** No application-filter Allow or Block entry with a specific executable path matching any of the three observed Java image paths was found among *these candidate rules*. It **does not** mean Java has no inbound connectivity, since `Any` program rules exist and IPv4/IPv6 WFP decisions, connection state, program service and other conditions are not evaluated.

## Further offline cross-check with the 04:25 policy-scope report

The earlier read-only policy report and the new Java-identity report agree on the count of **40 Any-program Allow candidates**, as well as all 40 ephemeral enumeration ordinals, for each of the eight private ports. The ordinals matched across the reports, which supports comparing these snapshots, **but they are not stable rule IDs** and cannot be used to locate a rule for deletion/configuration. Neither report provides the authenticated Windows rule identity or policy dependency information.

Of those 40 Any-program candidates in the **04:25 snapshot**:

- **36** have `protocol=Any`, a definite local-port match (effectively `Any` port), `local_address_scope=ANY`, `remote_address_scope=ANY`, `interface_scope=ANY`, `service_scope=ANY`, `authentication_scope=NotRequired`, `override_block_rules=False`, and an active rule profile overlapping Private/Public. These are the **broadest review-priority candidates** in the *metadata*, not proven inbound packet permits.
- **2** have `protocol=TCP` but `local_port_match=UNKNOWN` (named/dynamic port syntax), so their target-port relevance is unresolved.
- **2** have `protocol=Any`, definite port match but `local_address_scope=RESTRICTED_OR_COMPOSITE_REDACTED`; the exact permitted destination interfaces/addresses are not exported.
- The 40 Any-program candidates' remote address class is `ANY`, and the script had no filter errors. Profile distribution in the previous snapshot: 23 `Domain, Private`, eight `Domain, Private, Public`, nine `Any` (including the two unknown-port candidates).
- The previous 04:25 snapshot did not export a reliable executable or rule identity, and neither snapshot maps `RCON` and Paper Java to process-owning sockets in a simultaneous authoritative OS table.

**Important nuance:** the 36 broad candidates may correspond to legitimate Windows features or applications, and `Get-NetFirewallRule` candidate matching is not a simulation of the effective Windows Filtering Platform classification. Default inbound Block may be overridden by an applicable Allow, while a narrowly scoped Block for an unrelated program is not proof of Java isolation. No external exposure is established by these counts.

## Security decision and operational plan

**Day 12.10 is still FAIL**, final 12.11 operations E2E/12.12 live soak/12.13 Stable **BLOCKED**. Continue to preserve Golden 4/4, known-good cache, client connectivity and credentials.

**Stop endless equivalent inventories:** The report has now separated Java-specific program rules (zero), other-program rules (56), System scope (2) and Any-program rules (40), with 36 broadest candidates from the earlier metadata. Do not repeat these reports absent an actual environment change.

**Actionable engineering next stage, without unauthorized production mutations:**

1. Prepare **staging-only** candidate remote-inbound protection for the eight backend TCP ports, preserving 127.0.0.1/::1 local Velocity-to-Paper and GSC-to-RCON traffic. A Windows block rule could unexpectedly affect local traffic; never assert loopback exemption until demonstrated in a disposable local test.
2. Prepare a **private on-host review** mapping the 36 broadest candidates to their real Windows rule IDs/groups, publishers/services and why they exist. This may include Windows feature, VPN/overlay and remote-management rules; protect this metadata from publication. Do not disable by ephemeral ordinal.
3. Confirm impact on public Java TCP 25565–25567, Bedrock UDP 19132–19134 and GSC management 8787, plus Tailscale/IPv6 overlay paths. Capture original firewall rule export and reversible per-change rollback; preflight player count, Golden, GSC and known-good state.
4. Only after staging E2E and an explicit operator-approved live maintenance window may a narrowly scoped firewall security change be proposed. A separate **compensating firewall isolation** control does not establish **exclusive loopback socket binding**, so it cannot be used to force the existing `backend_ports_private` gate to PASS.
5. If neither authoritative IPv4+IPv6 bind-owner proof nor separately approved compensating-policy standard exists, keep strict gate open rather than claiming Stable.

## Readable summary

**No named Java firewall rule matched; 36 widely applicable Any-program Allow candidates are the first review priority; none was proved to expose a private backend.** No configuration change or server shutdown is currently justified solely by this evidence.

Source reviews: [04:25 firewall target scope](DAY12-PHASE10-FIREWALL-TARGET-RESULT-20261010.md), [source/CI Java correlation plan](DAY12-PHASE10-JAVA-RULE-IDENTITY-REVIEW.md), [compensating-controls constraints](DAY12-PHASE10-COMPENSATING-CONTROLS-REVIEW.md).
