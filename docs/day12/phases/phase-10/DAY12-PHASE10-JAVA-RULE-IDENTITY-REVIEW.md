# Day 12.10 — local Java executable-to-firewall application scope correlation

**State:** CODE + SYNTHETIC CI CHECK. **No production execution and no firewall changes.** Strict `backend_ports_private` remains **FAIL**.

## Scope and reason

The already-supplied `Day12-Firewall-Target-20261010-042526.json` showed, per private TCP Java/RCON port:

- 268 enabled inbound rules, 118 initial broad candidate rules; post-classifier fix **98 Allow candidate rules**, one program-specific Public Block rule and six unresolved candidates per port.
- **40** corresponding Allow candidates with `program_scope=ANY` and `remote_address_scope=ANY`; rules may be constrained by active profile, address, service, firewall precedence and other conditions.
- The 98 Allow candidates do **not** establish that 98 rules allow connections to Java. The original redacted report cannot match a `SPECIFIC_REDACTED` executable back to any running `java.exe`.

The next read-only implementation `tools/day12/Day12_Phase10_Java_Program_Rule_Match_READ_ONLY.ps1` runs **only on the server PC** and locally compares the Windows firewall `Get-NetFirewallApplicationFilter.Program` field against all currently running Java/javaw process `Win32_Process.ExecutablePath` values. No raw executable paths, process IDs, usernames, process command lines, Java arguments, server directories, rule GUIDs, rule names, IP addresses or secrets are exported.

A `program_scope=ANY` firewall rule remains a broad potential match without knowing process paths. A rule with the path of one **running Java executable** can be marked `MATCHES_RUNNING_JAVA_EXE`; **this does not identify the Paper backend process that owns port 25570–25573 or RCON 25575–25579**, since the server and unrelated tools can launch the same Java binary.

## Expected redacted output

The script reads all enabled inbound ActiveStore rules and their protocol/port/application filters; does not perform a TCP scan or alter firewall settings. It summarizes separately for eight backend TCP ports and three public Velocity TCP controls:

| Category | Meaning / limitation |
|---|---|
| `ALL_PROGRAMS` | Rule has no executable filter; could apply to Java if other filters match |
| `MATCHES_RUNNING_JAVA_EXE` | Rule specifies exact path of at least one currently running Java/javaw executable |
| `NO_RUNNING_JAVA_EXE_MATCH` | Rule specifies a different path from the **observed currently-running** Java executable set |
| `SPECIAL_SYSTEM_SCOPE` | Windows `System` pseudo-program; cannot infer a Java backend Allow |
| `PROGRAM_UNRESOLVED` | Missing, relative, malformed or wildcard application path; explicitly unresolved |
| `JAVA_IMAGE_INVENTORY_INCOMPLETE` | One or more Java executable paths could not be read, so negative matches cannot be trusted |

Known non-TCP protocols (UDP/ICMP/IGMP/IPv6 encapsulation) are explicitly excluded; unsupported protocols or named dynamic ports remain **UNKNOWN**. Program comparisons use local normalized Windows paths but no path strings appear in the JSON. Individual ordinal values are scoped to the local enumeration **in that one run only**; they are not stable firewall identifiers or edit requests.

## Status and safety invariants

- `SYNTHETIC_PASS` means parser/classifier worked in an isolated Windows CI fixture, **not** that the 40 broad Allow rules are safe or that a firewall rule works as intended on the server.
- `CAPTURED_FOR_REVIEW` means metadata was captured successfully, not a security PASS.
- `CHECK_REQUIRED` on inaccessible Java executable paths or rule filters; no fail-open logic.
- Explicitly forbidden: changing firewall rules, `auditpol`, RCON credentials, listening ports, server processes, Windows services, worlds, protected Golden checkpoints, or GSCM release mode.
- The first shared full firewall-target JSON is already preserved; the new process-aware scan adds distinct **program identity correlation**, not repeated identical TCP/WFP evidence.

## What this can resolve

It can narrow **specific-program** Allow/Block candidate lists to applications whose Java executable image is actually observed. It **cannot** prove the *effective* filtering verdict without the correct executable/service owner for each socket, rule precedence, local/remote address scope, multiple active network profiles, loopback handling, IPv6, overlay VPN routes and authenticated exceptions.

After the user reports one captured JSON, independently evaluate application-matching rules vs broad Any-program candidates. Do not recommend disabling unidentified rules or installing a port-wide Block before a documented staging test, operator-specific explicit approval, positive public TCP/Bedrock + internal proxy/RCON regression and reliable rollback.

The canonical Day12.10 `backend_ports_private` bind/owner gate remains **FAIL** until supported simultaneous runtime evidence; a separately proposed compensating firewall policy would require a distinct approval and explicit acceptance of its different assurance model.

## Operator command (after Windows synthetic CI PASS)

On the **Minecraft SERVER PC**, extract the updated Day 12 Operator Kit and run **once**:

`tools\day12\Day12_Phase10_Java_Program_Rule_Match_READ_ONLY.cmd`

Administrative read rights may be needed to enumerate `Win32_Process.ExecutablePath`. Send the latest `Desktop\Geumyi-Day12-Java-Rule-Match\Day12-Java-Rule-Match-*.json`; never submit raw firewall exports or Java process command lines. The script generates JSON in the operator's Desktop, performs no policy mutation, and produces exit 2 if required data is unavailable.

## Planned release-gate enforcement

1. Analyze Java-specific and all-program candidate rules without removing anything.
2. Review the four Paper backend owner identities and the Public 25565/25566/25567 controls without disrupting players.
3. In a disposable environment first, test any proposed firewall rule against client ingress, proxy-to-backend, RCON/GSC, and Bedrock UDP; abort on unexpected loopback block.
4. If a real change is still needed, seek explicit approval for exact commands, scope, maintenance window and per-rule rollback. No blind disable/cleanup.
5. Do not promote Day12.13 Stable until existing canonical mandatory gate and separate 12.11/12.12 release gates pass.

Related: [04:25 original firewall analysis](DAY12-PHASE10-FIREWALL-TARGET-RESULT-20261010.md) and [compensating controls review](DAY12-PHASE10-COMPENSATING-CONTROLS-REVIEW.md).
