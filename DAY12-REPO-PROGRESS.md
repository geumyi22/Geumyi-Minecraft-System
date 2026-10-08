# Day 12 — Repository / Live Progress

Updated: 2026-10-09 KST

This file separates **work that can be completed from GitHub/CI** from **work that requires the real server PC or real clients**. Source/CI completion never substitutes for live evidence.

| Phase | Repository / tooling | Live evidence |
|---|---|---|
| 12.0 Final Freeze | ✅ baseline files + 12.0A/12.0B tools prepared | ✅ 12.0A READY (2026-10-09 02:45 KST), 12.0B PASS (03:23 KST); 4/4 Golden FULL backups verified/protected |
| 12.1 Resource/DataPack | ✅ manifest/preflight/guarded Java apply/rollback tooling | 🟡 04:22 live READ-ONLY inventory CAPTURED for 4 servers; managed manifest has 0 entries, Geyser inventory-only. Exact configure/apply/Java+Bedrock E2E pending |
| 12.2 Component inventory | ✅ host + four-server runtime JAR fingerprints acquired; canonical 0.5.4 Agent file verified present, Day10 Lobby aliases recognized | 🟡 06:07: StatusAgent **0.5.4 exists at Runtime/Agent and matches configured filename**; 0.5.3 coexists there, legacy 0.4.5 elsewhere. Hash provenance and actual process-launched JAR still unverified; no deletion/redeployment |
| 12.3 Whole-system health | ✅ read-only health tool prepared | ✅ 04:23 real-server read-only health report CAPTURED_NO_MANDATORY_FAIL: 15 PASS / 0 WARN / 0 FAIL. Does not close 12.10 security bind gate |
| 12.4 Storage/log lifecycle | ✅ dry-run/Trash/LogTrash tools prepared | 🟡 04:23 live DRY-RUN CAPTURED, 4/4 backup entries protected; 0 backup/log candidates, reclaim 0, disk 364.82 GiB free. No Apply needed based on this snapshot; lifecycle policy approval still pending |
| 12.5 Security | ✅ firewall 06:13 full READ-ONLY inventory + 06:21 ActiveStore scope capture + 8787 GSC authentication subcheck | 🟡 38 potentially applicable broad Allow rules, all 38 active-profile overlap; GSC ProgramData BUILTIN_USERS inherited Write Allow still needs effective ACL review. **Operator-reported independent-PC 8787/TCP reached and unauthenticated GET `/api/v1/info` returned HTTP 401 (auth-required endpoint subcheck PASS)**; this is not all-endpoints auth verification or an Internet exposure test. Actual WFP enforcement and rule identity/purpose still pending |
| 12.6 Trusted release | ✅ fail-closed closure gate + final Stable release workflow + reproducibility/provenance prepared | ⏳ final Stable promotion after every live gate |
| 12.7 Offline/cache | ✅ known-good cache audit/build and recovery kit tooling prepared | ✅ Build PASS (03:45 KST) and 04:23 READ-ONLY Audit CAPTURED (84 cache artifacts); ⏳ actual offline startup/recovery E2E still pending |
| 12.8 DR | ✅ synthetic DR + Recovery Kit **PASS** — run `37670892599` | production files untouched; synthetic/non-production scope satisfied |
| 12.9 UX cleanup | ✅ obsolete installer 4.3.0 README payload retired; installer baseline = 4.3.8/+117; System CI `37669908817` PASS | ⏳ only runtime UI observations if any |
| 12.10 Final verifier | ✅ canonical read-only verifier, bind evidence and independent second-PC LAN proof tooling | 🟡 **LAN reachability subcheck PASS (05:52 KST): 3/3 public TCP reachable, 0/8 private Java+RCON reachable from separate PC**. ❌ Canonical final verifier remains 18 PASS / 0 WARN / 1 FAIL (`backend_ports_private`); Wild/Lobby/RCON runtime listen-address proof absent. No gate bypass |
| 12.11 Final E2E | ✅ exact report/checklist prepared | ⏳ reboot + Java + Bedrock + GSCM + operations |
| 12.12 Soak | ✅ start/end collector prepared | ⏳ 8–12 h where practical + review |
| 12.13 Final release | ✅ maintenance handoff + fail-closed closure workflow prepared | ⏳ signed Stable release after gates |

## 2026-10-09 04:19 KST — operator TCP diagnostic evidence

- Real Windows read-only capture `Day12-TCP-Diagnostic-20261009-041918.json` (timestamp 04:19:20 KST): `result=CAPTURED`, `mutation_performed=false`.
- The previous PowerShell `$PID` assignment exception is fixed: netstat provider now reports `OK`, exit 0, with 924 lines scanned. No target-port `LISTENING` rows were returned; displayed remote-port samples are `TIME_WAIT` and are **not** proof of listening/bind addresses.
- Native Windows TCP listener inventory reports `127.0.0.1:25571` and `127.0.0.1:8790`. PowerShell and .NET each enumerate 9 total listeners but match none of the expected target ports.
- Loopback connect succeeds for TCP 25570/25571/25573; a successful localhost connection **cannot** establish whether a socket also binds a public interface. No 25572 listener proof was captured.
- **12.10 remains FAIL/PENDING.** Do not alter `FINAL-RELEASE-GATES.json`, promote Stable, or infer private binding for absent listener rows.
- Safe next step: inspect `Day12_Collect_All_READ_ONLY.cmd` runtime inventory and review the real server lifecycle/listeners together before any configuration change. This is not a request to repeat already-protected Golden backups.

## 2026-10-09 04:22–04:23 KST — consolidated operator report

Operator-supplied archive `Geumyi-Day12-READONLY-20261009-042239.zip` was **reviewed locally, not uploaded to the public repository**. Collector summary: 7 phase collectors CAPTURED (exit 0), final verifier CHECK (exit 2), overall `CHECK_REQUIRED`; no live mutation reported. Key cross-checks:

- 12.0A new baseline: 18 checks PASS, mandatory failures none, Golden checkpoint readiness true; GSC Host 4.3.8 and four configured profiles.
- 12.1 preflight: 4 server inventories, zero configured managed-content manifest entries, Bedrock/Geyser auto-apply unsupported until exact locations confirmed. No managed content deployed.
- 12.2: 15 component/policy records captured; installed fingerprints for five in-house Java components remain pending. The Other backend is OFFLINE by recorded state; do not infer error or auto-start.
- 12.3: real health 15 PASS / 0 WARN / 0 FAIL; three Java and three Bedrock entry probes PASS, service Running, update residue zero. Probe PASS is not the same as real-client E2E.
- 12.4: dry-run, **0 deletion/Trash candidates** and **0 reclaim bytes**; 4/4 backups protected, 364.82 GiB free, no mutation. Do not run lifecycle Apply without new review.
- 12.5: read-only runtime security report flags `tcp_listener_inventory_inconclusive=true`; GSC loopback bind reported, seven firewall Allow rules recorded without sufficient port-scope evidence in the report. ACL and actual bind review not closed.
- 12.7: Audit CAPTURED 84 cached artifacts; no live-file changes or network requirement. Actual offline-start E2E remains pending.
- 12.10: **18 PASS / 0 WARN / 1 FAIL**: `backend_ports_private` reports zero listener rows, missing live online backend TCP 25570/25571/25573, and `tcp_inventory=unavailable`. This is **absence of evidence**, not proof of an actual public bind. Do not weaken the fail-closed gate or mark 12.10 PASS.

Only sanitized derived findings are committed. Existing Golden backups, artifact cache and release gate JSON remain unchanged.

## 2026-10-09 — 12.10 targeted bind evidence tool (repository-side only)

- Prepared `tools/day12/Day12_Phase10_Bind_Evidence_READ_ONLY.ps1` and its one-click `.cmd` launcher. The collector reads only bind/port metadata from the configured Paper `server.properties`, checks two rounds of Windows TCP listeners and redacts non-loopback addresses. It does **not** modify configuration, firewall, server processes, backup state or update policy.
- Synthetic tests require the netstat parser to distinguish loopback, wildcard and IPv6 loopback and to ignore `TIME_WAIT`; configuration tests require empty `server-ip` to remain a risk rather than passing as private.
- The new report is `CAPTURED_REVIEW_REQUIRED`, **not security PASS**. The existing `backend_ports_private` gate and `FINAL-RELEASE-GATES.json` remain fail-closed. A separate real-server output is required to determine whether the issue is an actual bind configuration risk or a Windows listener-inventory gap.
- The `day12-operator-kit` includes the new collector. Full CI outcome must be checked independently of the synthetic step result.

## 2026-10-09 05:27 KST — binding evidence (operator supplied)

- File: `Day12-Bind-Evidence-20261009-052746.json` (**reviewed locally; not committed**), read-only result `CAPTURED_REVIEW_REQUIRED`, no reported mutation or exported secrets.
- **All four** Wild/Playground/Other/Lobby server directories and `server.properties` are present. All four explicitly specify `server-ip=127.0.0.1`; Java ports 25570–25573 and RCON ports 25575/25576/25577/25579 match the expected mapping; RCON enabled in the reported configurations. The collector recorded SHA-256 hashes, not full config contents.
- Two listener rounds: `Get-NetTCPConnection` and `IPGlobalProperties` each enumerated **9 total** listeners and **0 matching target-port rows**. `netstat` exited successfully with **901 lines** both times and **0 matching target-port LISTENING rows**.
- Zero **observed** non-loopback private listeners is **not** proof of private runtime binds because **no relevant listener was observed at all**. The collector did **not** record whether the backend servers were online at the time. Previous 04:23 GSC online status cannot be assumed unchanged at 05:27.
- **12.10 stays blocked**. Treat server config scope as PASS / active runtime socket exposure as UNVERIFIED. Do not mark `backend_ports_private` PASS, change firewall or backend properties, start Other automatically, delete backups, or promote Stable.
- Next step: correlate **same-time** GSC online state, loopback TCP connect result and listener inventories in a refreshed read-only collector; if listeners remain invisible for a demonstrably online backend, investigate host process/network context without weakening the final gate.

## 2026-10-09 05:34 KST — simultaneous live reachability vs listener enumeration

- Operator-supplied `Day12-Bind-Evidence-20261009-053405.json` (not uploaded to GitHub): read-only `CAPTURED_REVIEW_REQUIRED`, GSC Host `Running`, no reported mutations.
- Before **and** after TCP inventory: GSC fleet Wild/Playground/Lobby **ONLINE**, Other **OFFLINE**. Same capture: localhost Java TCP **connects** to 25570/25571/25573, while 25572 does not (consistent with Other OFFLINE).
- 4/4 `server.properties` explicitly have `server-ip=127.0.0.1`, expected Java (25570–25573) and RCON (25575/25576/25577/25579) numbers, and `enable-rcon=true`. These are **configuration-level** findings; RCON actual socket bind address remains unverified.
- Both rounds of 3 providers (Get-NetTCPConnection, IPGlobalProperties, netstat) found **0 target listener rows** although 3 online backends accept localhost connects. `netstat` read 895 then 913 lines; Windows listener enumeration is currently inconclusive. No observed non-loopback bind does **not** prove absence of exposure when the inventory is empty.
- Updated the read-only bind collector to also capture an independent **GetExtendedTcpTable** IP Helper provider, non-sensitive Java PID listing, elevation status, and **redacted netsh portproxy target-port mentions**. Native provider and portproxy metadata still cannot turn missing socket evidence into PASS.
- **12.10 remains FAIL/PENDING; final signed Stable/Maintenance gate remains blocked.** Do not edit configurations, RCON settings or firewall rules from these observations alone.

## 2026-10-09 05:40 KST — actual native TCP comparison and remote LAN probe plan

- Operator-submitted `Day12-Bind-Evidence-20261009-054006.json` reviewed locally, **not uploaded** to public GitHub. Read-only, elevated=true; native `GetExtendedTcpTable` reports `127.0.0.1:25571` (Java PID present in process list) and `127.0.0.1:8790`, stable over 2 passes. No target port was reported by `Get-NetTCPConnection`, .NET `IPGlobalProperties`, or `netstat`; native reported 11 total listener rows, other APIs 9. This is a genuine cross-provider enumeration inconsistency.
- Wild/Playground/Lobby remain GSC ONLINE both before/after capture and Java 25570/25571/25573 accept localhost TCP. Other is OFFLINE and 25572 does not accept localhost. All four Paper profiles retain `server-ip=127.0.0.1`. No relevant Windows `netsh portproxy` target port mentioned. RCON actual binds were not observed.
- **Confirmed runtime loopback listener proof only for Playground 25571**. Wild/Lobby listener binds, all RCON bind addresses, and remote reachability remain UNVERIFIED. The absence of a listed non-loopback listener is not proof of an inaccessible port. Do not mark 12.10 PASS, loosen the mandatory gate or alter the production configuration.
- Prepared `tools/day12/Day12_Phase10_LAN_Proof_READ_ONLY.cmd` for execution on a **different Windows PC** on the same LAN. It prompts for the server's private IPv4 (not exported), checks public TCP 25565/25566/25567 as positive controls and private Java+RCON TCP ports as negative/alert candidates, exports only boolean reachability by port. No networking policy, credentials, or runtime files are changed. Even all-negative results do not prove loopback bind; any reachable private port requires investigation.
- CI synthetic test and Operator Kit packaging added; still require user-performed remote test. This is a new evidence path, not an E2E success assertion.

## 2026-10-09 05:52 KST — independent LAN access proof received

- Operator-submitted `Day12-LAN-Proof-20261009-055112.json` reviewed locally; source JSON, entered LAN IP and machine details **not uploaded to GitHub**. Tool reports `read_only=true`, `synthetic=false`, `mutation_performed=false`, `CAPTURED_REVIEW_REQUIRED`.
- Remote Windows PC positive controls **3/3 CONNECTED** for public Java TCP **25565, 25566, 25567**. Test-side GSC Host service check was false, supporting a separate tester machine; exact network topology was not independently authenticated.
- Internal Paper TCP **25570–25573: 0/4 CONNECTED**. Internal RCON TCP **25575/25576/25577/25579: 0/4 CONNECTED**. Overall **0/8 private TCP ports remotely reachable** from the tested private-LAN path, with positive controls established.
- **12.10 LAN-access negative test: PASS for tested LAN vantage point only.** This does **not** prove actual loopback socket bind, rule out all other network paths (e.g. Tailscale/external exposure), or replace missing process-socket evidence. Firewall/routing could independently block the connection. The previously observed native loopback bind for Playground 25571 is additional direct runtime evidence.
- **Canonical `backend_ports_private` gate remains FAIL** until all online backend bind addresses and security boundary are conclusively established; protected Golden 4/4, known-good cache, release gate, firewall and server state remain unchanged. Next work should prioritize 12.2 component JAR fingerprints and 12.5 ACL/firewall rule scope while preserving the unresolved 12.10 gate; avoid repeating the same LAN check without meaningful environmental change.

## 2026-10-09 — phase 12.2/12.5 read-only evidence collector prepared

- The prior 12.2 script only emitted `PENDING_LIVE_FINGERPRINT` placeholders for GST/GDS/StatusAgent/Technology/Chemistry. Added `Day12_Phase2_5_Integrity_Security_READ_ONLY.ps1/.cmd` for an explicit, user-run follow-up on the **actual server host**.
- The targeted collector enumerates `plugins/*.jar` **without recursion**, selects the four in-house Java plugin families (GST, GDS, Technology, Chemistry), computes SHA-256, reports duplicates/missing expected slots, and compares filenames/version hints to repository `deploy/components.json` (currently GST 1.1.1, GDS 1.1.1, Technology 0.1.4, Chemistry 0.4.1). Agent 0.5.4 is host-scoped; detection uses **bounded candidate directories**, so absent matches do not prove absent installation.
- The same read-only capture summarizes GSC/plugins directory ACL roles and enabled inbound firewall rule filters (target-port intersection, TCP/UDP/Any, remote-scope classification, program-scope classification). Rule names, user identities, raw remote IPs, program paths and full server paths are **not serialized**. It is not an evaluation of effective Windows Filtering Platform authorization or an external security PASS.
- No trusted upstream artifact SHA-256 baseline is asserted from a filename alone; final 12.2 component authenticity remains pending if provenance cannot be established. The 12.5 audit and final 12.10 bind gate remain **fail-closed**. No old backups or caches are regenerated.

## 2026-10-09 06:02 KST — phase 12.2 + 12.5 user capture

- Reviewed privately `Day12-Integrity-Security-20261009-060048.json` (`CAPTURED_FOR_REVIEW`, read-only, real-host). **Raw diagnostic JSON was not committed**; no mutation or secret export reported.
- 17 component/location records. Wild has GST 1.1.1, GDS 1.1.1, Technology 0.1.4 and Chemistry 0.4.1 matching manifest filenames, all with recorded SHA-256. Playground has expected GST/GDS and no Technology/Chemistry (not target). Other has expected GST/GDS/Technology/Chemistry files (its online status is separately recorded OFFLINE, not inferred from file presence).
- Lobby GST/GDS have shortened filenames `GeumyiServerTools-1.1.1.jar` and `GeumyiDiscordStatus-1.1.1.jar` with hashes/sizes different from Wild/Other. **GitHub `tools/day10/finish_day10.ps1` explicitly deploys these shorter Lobby names**, so names are known intentional aliases, not automatically an upgrade/fix request. **Binary equality/provenance cannot be asserted from the filenames**. No plugin JAR was altered.
- Agent 0.4.5 was found under one limited host candidate directory, while `deploy/components.json` expects 0.5.4. Crucially, the old collector **omitted canonical `ProgramData/GeumyiServerCenter/Runtime/Agent`**. The GSC Setup code installs 0.5.4 at that canonical runtime path, so this capture does **not** establish an old runtime agent. New collector checks canonical/configured runtime and labels legacy copies separately. Do not remove 0.4.5 or assert mismatch until new evidence.
- GSC ProgramData folder ACL summary has an **inherited BUILTIN_USERS write/modify Allow ACE** (one broad write-allow warning). Four plugin folder ACL summaries have no such broad Allow but contain inherited **Everyone write/modify Deny**. ACL flags are a review signal, not a confirmed exploitable vulnerability or proof all writers are blocked; modifying inheritance/permissions now may interrupt backup/update behavior.
- Firewall collector read 268 enabled inbound rules, selected 149 because old matching logic treated every **LocalPort=Any** as matching all 16 Minecraft/management candidate ports. This is **overinclusive**, not proof that 149 rules opened any particular port. Some entries are program- or service-scoped; full effective Windows Firewall policy was not established. New collector now separates explicit target port matches from broad `Any`-port candidates and records service scope. The separate 05:52 LAN test remains **3/3 public reachable and 0/8 private reachable from that tested vantage point**.
- **12.2 fingerprint capture is partial, 12.5 final security review remains pending, 12.10/Stable fail-closed**. Prior Goldens/cache/lifecycle were not changed. Follow-up: re-run only updated focused READ-ONLY collector once; inspect canonical Agent path and accurate firewall classification before proposing any installation, ACL, or firewall changes.

## 2026-10-09 06:07:59 KST — canonical Agent proven present; firewall scan incomplete

- Operator supplied `Day12-Integrity-Security-20261009-060757.json` privately; **source file was not committed**. Real server run, `CAPTURED_FOR_REVIEW` combined report, `read_only=true`, `mutation_performed=false`.
- **12.2**: StatusAgent 0.5.4 JAR present under canonical `Runtime/Agent`, matches `server.json` configured `agent.jar_name`, and has a collected SHA-256 fingerprint. 0.5.3 JAR also exists in that runtime folder; 0.4.5 resides in a **legacy** Agent folder. These are *files*, not confirmed active processes. Do **not** delete old JARs or assume runtime executed 0.5.4 until the running process/command path is corroborated. Trusted release artifact hash evidence remains unavailable.
- Wild, Playground and Other have expected designated plugin JAR filename/hash combinations; Lobby GST/GDS are the Day10 documented shorter aliases with different file SHA-256. No duplicate active plugin JAR candidates were identified by exact component-family scan. Not a binary provenance PASS.
- **12.5**: GSC ProgramData ACL still has one inherited `BUILTIN_USERS` Write/Modify Allow ACE. Four backend plugin-folder ACLs contain inherited `Everyone` Deny Write/Modify ACE; these are not automatically equivalent to effective-access assessments. Do not change access inheritance while server operations rely on it.
- **Firewall scan FAILED**: 268 enabled inbound firewall rules were counted, but `firewall.status=ERROR_OR_UNAVAILABLE`, `matching_rules=[]`, and zero per-filter retrieval failures were recorded. This **does not mean no firewall rules apply**. The prior collector's `if { @() }` for wildcard ports likely emitted a null result under PowerShell StrictMode, aborting before serialization; this is a **diagnostic hypothesis**, not an established root cause. Source fix forces concrete arrays, isolates per-rule exceptions, writes sanitized stage+exception type, and changes the report to fail-closed `CHECK_REQUIRED` if firewall capture is incomplete. No firewall changes.
- **12.2 file inventory partially supported / 12.5 firewall verification CHECK / 12.10 existing canonical fail closed / 12.13 Stable pending**. Once new CI succeeds, operator may run just the updated 12.2+12.5 read-only collector once; never repeat Golden backups or prior LAN test.

## 2026-10-09 06:13:57 KST — firewall full collection succeeded

- Operator-supplied `Day12-Integrity-Security-20261009-061224.json` was reviewed **privately**, not committed. `read_only=true`, `synthetic=false`, `mutation_performed=false`, `result=CAPTURED_FOR_REVIEW`.
- **Firewall inventory reliability recovered**: `status=CAPTURED`, 268/268 enabled inbound rules enumerated and processed, **0** per-rule processing errors, **0** port filter failures. Earlier `ERROR_OR_UNAVAILABLE` issue has been addressed in the observed operator run. This is capture success, **not** a security PASS.
- **47 selected** inbound Allow rules from the project-/port-/broad-criteria collector: **40** have `LocalPort=Any`, **3** have explicit target-port intersection, **4** named project rules have `UNKNOWN_OR_NON_TARGET` port scope. Of those, **38** are candidate allow rules with `Program=Any`, `LocalPort=Any`, protocol TCP/UDP/Any; all 38 also report `RemoteAddress=Any` and `Service=Any`. Profile mix: 23 Domain+Private; 8 Domain+Private+Public; 7 Any. These may be constrained by other firewall policy aspects not captured and do **not** establish open sockets or confirmed exposure.
- Explicit target-port Allow rules found: TCP **25565,25566** any remote; UDP **19132,19133** any remote; TCP **8787** remote `LocalSubnet` (or composite). No explicit allow of Java internal backend 25570–25573 or RCON 25575–25577/25579 was selected. However broad wildcard rules could still cover them if active and applicable, so **absence of explicit rules is not evidence of deny**.
- GSC ProgramData ACL still reports one inherited BUILTIN_USERS write/modify Allow ACE. All four plugin directories have no recorded broad write Allow but inherited Everyone write/modify Deny ACE. **Effective NTFS access** and effect on GSC runtime/backup ownership are not established. Do not modify ACL inheritance based on this report alone.
- The expected **StatusAgent 0.5.4** JAR is found at canonical `Runtime/Agent` matching configured jar filename; 0.5.3 resides alongside and 0.4.5 in a legacy location. No active-process signature or upstream reference hash was established. Wild/Playground/Other plugin fingerprints and Day10 Lobby alias statuses are unchanged.
- Previously established separate-PC LAN proof remains 3/3 public TCP accessible, **0/8** private backend/RCON accessible from tested LAN path. That does not rule out other interfaces or firewall profile changes. **12.5 effective exposure review remains OPEN and 12.10 backend bind canonical gate FAIL**. Do not promote Stable or edit `FINAL-RELEASE-GATES.json`.
- Next useful work: narrow **38 broad Any/Any Allow candidates** by active profile, rule origin/policy store, interface/service/application/package restrictions **without changing firewall**; independently validate canonical backend bind evidence. No repeat of Golden/cache/previous LAN testing.

## 2026-10-09 — follow-up ActiveStore rule-origin evidence tool (repository-only)

- Based on the 06:13 full host firewall inventory, added `tools/day12/Day12_Phase5_Firewall_Scope_READ_ONLY.ps1/.cmd`. It reads **ActiveStore** (currently effective Windows Firewall rules from applicable stores, distinct from only local PersistentStore), current network categories, firewall profiles and the **Any-port + Any-program Allow candidate** subset. Microsoft's NetSecurity commands support these filtered read-only queries.
- Reports *sanitized* profile, origin-type, active-network-category overlap, interface type/scope, local/remote address scope, service/authentication/edge flags for only broad candidates; never exports rule names/IDs, IPs, interface aliases, program paths, tokens, or hostnames. Reports fail-closed `CHECK_REQUIRED` if relevant rule/profile queries fail, never 12.5 security PASS.
- The 06:13 full scan, prior LAN reachability proof, component hashes, backups and GSC baseline **remain valid**. Do not repeat the previous full collector; when needed run the **narrow ActiveStore scope** only on the actual server PC, administrator privileges, one time.
- This tool does not alter Windows Firewall settings, OS ACL, server processes, known-good cache, GSC update policy, or `FINAL-RELEASE-GATES.json`.

## 2026-10-09 06:21:08 KST — ActiveStore firewall scope evidence received

- User supplied `Day12-Firewall-Scope-20261009-062054.json` privately; **raw JSON not committed**. `phase=12.5-firewall-scope`, `synthetic=false`, `read_only=true`, `result=CAPTURED_FOR_REVIEW`, `mutation_performed=false`, `secrets_exported=false`.
- Windows network categories on this server are **Private and Public**, and ActiveStore firewall profiles Domain/Private/Public are **enabled**, each with default inbound **Block**, `AllowInboundRules=True`, `AllowLocalFirewallRules=True`. These defaults do not override applicable Allow rules.
- ActiveStore read **266 inbound Enabled Allow** rules, `port_application_filter_failures=0`, **38 broad** candidates (`LocalPort=Any`, `Program=Any`, protocol `Any`); all 38 have `matches_active_network_categories=true`, `RemoteAddress=Any`, `Service=Any`, `InterfaceScope=Any`, `InterfaceType=Any`, `PolicyStoreSourceType=Local`, `PrimaryStatus=OK`, `Authentication/Encryption=NotRequired`, and no Geumyi project naming match. 36 candidates have `LocalAddress=Any`, while two have restricted/composite local-address scope.
- **Security implication:** a significant collection of *potentially applicable* broad Allow rules exists even though inbound defaults are Block. This is a **manual audit finding** that needs rule-origin/purpose analysis before any modification. `EdgeTraversalPolicy=Allow` on some candidates is not equivalent to an externally reachable socket or verified Internet traversal. In particular, do not claim 38 open public ports or an actual exploit. WFP/block precedence, local addresses/interfaces, package/IPsec conditions and currently bound services were not definitively validated.
- Previously observed private-LAN reachability controls: **3/3 public Java port checks reachable**, **0/8 backend/RCON private-port checks reachable** from the tested second PC. That evidence limits this one tested path only. The explicit allow of management **8787/TCP LocalSubnet** from prior 06:13 inventory has *not been tested as a second-PC control*; do not assume 8787 external availability or absence.
- **12.5 source collection PASS, safety evaluation OPEN**; 12.10 canonical `backend_ports_private` FAIL remains and Stable is BLOCKED. No firewall/ACL/service/plugin/backup/Golden/cache or release gate modification was performed.
- Next focused evidence (without repeating full inventories): map these broad rules to local identifiers/origin categories privately and examine whether they can affect GSC management/backend sockets; independently verify the host's live 8787 listener scope or test only TCP connect from a second LAN machine. Do not remove unspecified rules in bulk or auto-promote Stable.

## 2026-10-09 ~06:24 KST — GSC 8787 cross-LAN TCP connection observed

- Operator reported `TcpTestSucceeded=True` when repeating TCP 8787 check from the **secondary PC** to the server PC private-LAN IP (earlier self-test had `SourceAddress=RemoteAddress` and was inconclusive; this follow-up reported only the Boolean, not an independently observed SourceAddress). This is positive **TCP reachability indication on the LAN**, not a check of API authentication, public-Internet exposure, or successful administration.
- Source investigation: `GSC/ServerCenter/cmd/host/main.go` constructs its HTTP listener at `0.0.0.0:<cfg.Port>` (despite an older `Config.Bind` default of `127.0.0.1`). This is **intentional GSCM private remote transport design**; requests then traverse `mobileNetworkGuard` in `v42_mobile.go`, which permits loopback and restricts remote clients to configured LAN/Tailscale private scope when mobile is enabled. Protected API routes such as `GET /api/v1/info` use `requireAuth` from `v41_control.go` with token or paired-device credentials. Only loopback connections may bypass credentials if `allow_loopback_no_auth` is set.
- **Expected 8787 reachability is not an automatic security FAIL**: it must be distinguished from back-end Paper and RCON ports 25570–25573 / 25575–25577 / 25579, which should remain private. An unauthenticated read-only request **from the secondary PC** to `GET http://<server-private-LAN-IP>:8787/api/v1/info` should return **HTTP 401** (or HTTP 403 if blocked by the remote network guard). A 200 without supplied credentials would require immediate security investigation; do not submit credentials or response bodies. The HTTP test was **not performed or verified** as part of this report.
- The 06:21 broad ActiveStore firewall candidate analysis remains a manual-review item; do not mass-disable firewall Allow rules or GSCM remote management. **12.5 review OPEN, 12.10 canonical backend binds FAIL, Stable BLOCKED**; no production mutation.

## 2026-10-09 ~06:25 KST — unauthenticated LAN GET to GSC 8787 rejected

- **Operator-reported**: on secondary PC, read-only request `GET http://<server-LAN-IPv4>:8787/api/v1/info` with **no Authorization token** returned **HTTP 401 Unauthorized**. No response body, token, private IP, or credential was uploaded to GitHub. Previous operator report on the same secondary PC recorded TCP 8787 connect `True` (no complete source-address display was supplied for that run).
- **12.5 GSC remote authentication endpoint subcheck PASS (scoped only to this request/path/network vantage)**: port 8787 accepts private LAN transport as designed; this protected `/api/v1/info` path rejects missing credentials. This does not test other endpoints, pairing behavior, transport encryption, remote Internet/Tailscale exposure, or confirm overall WFP rule effectiveness. GitHub source indicates `0.0.0.0:<configured-port>` plus `mobileNetworkGuard` and `requireAuth` token/device checks, but source reading does not substitute for all live behaviors.
- This report is **not evidence that the 38 broad Any/Any firewall rules are harmless**. GSC ProgramData's BUILTIN_USERS inherited write allow remains unresolved, as do server backend listener addresses. **12.5 final security gate stays OPEN; 12.10 canonical backend_ports_private FAIL; 12.11/12.12 live E2E/soak pending; 12.13 Stable BLOCKED**.
- No action taken on live firewall, ACLs, GSC binaries/config, tokens, devices, backups, or running servers. Do not repeat successful 8787 endpoint check unless environment changes.

## 2026-10-09 — phase 12.5 read-only rule purpose + precise ACL follow-up prepared

- Previous **06:21 ActiveStore full scan** and **06:25 operator-reported unauthenticated GSC 8787 GET HTTP 401** remain the current server evidence; do not repeat those tests. Main unresolved 12.5 findings: **38 active-profile-overlapping broad inbound Allow candidates** of unknown specific purpose, and inherited BUILTIN_USERS writable ACE at GSC ProgramData.
- Added `tools/day12/Day12_Phase5_Rule_ACL_Review_READ_ONLY.ps1/.cmd` for a single targeted read-only capture **on the actual server PC**. The rule scanner only selects active inbound Allow rules with port Any, program Any and TCP/UDP/Any protocol, then assigns **heuristic category hints** (Windows feature, VPN/overlay, virtualization, remote management, Minecraft/Java, gaming, discovery, other); it does **not** assert signed publisher, rule origin, necessity, exploitability or effective packet permit. Raw rule names, remote IPs, user identities and executable paths are **never emitted**.
- ACL inspection is limited to GSC ProgramData dir, its `server.json` **file ACL without reading secret contents**, Runtime dir, Runtime/Agent dir and 0.5.4 JAR ACL. Writes detailed coarse SID categories and per-ACE bit flags (write-data, append, delete, change-permissions, ownership, write-attributes), inheritance and ACL inheritance protection. It does **not** compute an actual access token's effective rights and does not touch disk permissions.
- The current 12.5 security gate remains OPEN. No firewall / ACL / process / binary / token / backup / Golden / cache / version or FINAL-RELEASE-GATES modifications are authorized by this preparation. Tool validation is CI/synthetic only until operator supplies real-host output.

## Safety boundary

No live item above is marked PASS unless real-machine/client evidence exists. In particular, the repository currently **cannot** be switched to Maintenance Mode and the final Stable release gate remains closed.


## Verified repository evidence

- Latest Day 12 Safety CI on commit `0e4c5db`: `37828017071` — **PASS** (includes synthetic Windows native TCP diagnostic; not a live-port security PASS)
- Latest Security / SBOM / GSC reproducibility on current pre-live toolchain: `37672459736` — **PASS**
- Synthetic DR / Recovery Kit: `37670892599` — **PASS**
- System CI after installer cleanup: `37669908817` — **PASS**
- Host Test after installer cleanup: `37669908646` — **PASS**
- Latest Day 12 Operator Kit: `37672459977` — **PASS**

Therefore all currently defined **repository-side mandatory gates are PASS**. Final Stable/Maintenance remains blocked solely because live gates are intentionally pending.
