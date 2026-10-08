# Day 12 — Repository / Live Progress

Updated: 2026-10-09 KST

This file separates **work that can be completed from GitHub/CI** from **work that requires the real server PC or real clients**. Source/CI completion never substitutes for live evidence.

| Phase | Repository / tooling | Live evidence |
|---|---|---|
| 12.0 Final Freeze | ✅ baseline files + 12.0A/12.0B tools prepared | ✅ 12.0A READY (2026-10-09 02:45 KST), 12.0B PASS (03:23 KST); 4/4 Golden FULL backups verified/protected |
| 12.1 Resource/DataPack | ✅ manifest/preflight/guarded Java apply/rollback tooling | 🟡 04:22 live READ-ONLY inventory CAPTURED for 4 servers; managed manifest has 0 entries, Geyser inventory-only. Exact configure/apply/Java+Bedrock E2E pending |
| 12.2 Component inventory | ✅ read-only JAR SHA-256 audit; Day10 lobby alias recognition & active agent runtime path check now added | 🟡 06:02 live SHA-256 inventory CAPTURED: Wild/Playground/Other expected JAR filenames present; Lobby GST/GDS have **Day10-known short filenames but different hashes**; host limited search found legacy Agent 0.4.5 (not proven active). Updated canonical Runtime/Agent check pending. Trusted release authenticity still unverified |
| 12.3 Whole-system health | ✅ read-only health tool prepared | ✅ 04:23 real-server read-only health report CAPTURED_NO_MANDATORY_FAIL: 15 PASS / 0 WARN / 0 FAIL. Does not close 12.10 security bind gate |
| 12.4 Storage/log lifecycle | ✅ dry-run/Trash/LogTrash tools prepared | 🟡 04:23 live DRY-RUN CAPTURED, 4/4 backup entries protected; 0 backup/log candidates, reclaim 0, disk 364.82 GiB free. No Apply needed based on this snapshot; lifecycle policy approval still pending |
| 12.5 Security | ✅ read-only ACL + firewall filter inventory enhanced to distinguish Any-port from explicit-port rules | 🟡 06:02 ACL **BUILTIN_USERS inherited write-allow** reported at GSC ProgramData; 4 plugin dirs have no broad write-allow but inherited Everyone write-deny; firewall 268 enabled inbound rules inspected, 149 selected in legacy algorithm dominated by Any-port rules (NOT 149 specific port openings). Real rule applicability and ACL effective write rights pending |
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
