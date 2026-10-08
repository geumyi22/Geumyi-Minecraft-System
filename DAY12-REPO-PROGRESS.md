# Day 12 — Repository / Live Progress

Updated: 2026-10-09 KST

This file separates **work that can be completed from GitHub/CI** from **work that requires the real server PC or real clients**. Source/CI completion never substitutes for live evidence.

| Phase | Repository / tooling | Live evidence |
|---|---|---|
| 12.0 Final Freeze | ✅ baseline files + 12.0A/12.0B tools prepared | ✅ 12.0A READY (2026-10-09 02:45 KST), 12.0B PASS (03:23 KST); 4/4 Golden FULL backups verified/protected |
| 12.1 Resource/DataPack | ✅ manifest/preflight/guarded Java apply/rollback tooling | 🟡 04:22 live READ-ONLY inventory CAPTURED for 4 servers; managed manifest has 0 entries, Geyser inventory-only. Exact configure/apply/Java+Bedrock E2E pending |
| 12.2 Component inventory | ✅ capture tool prepared | 🟡 04:22 live inventory CAPTURED (15 records); GST/GDS/StatusAgent/Technology/Chemistry exact runtime JAR fingerprints still pending. Other recorded OFFLINE, no automatic start |
| 12.3 Whole-system health | ✅ read-only health tool prepared | ✅ 04:23 real-server read-only health report CAPTURED_NO_MANDATORY_FAIL: 15 PASS / 0 WARN / 0 FAIL. Does not close 12.10 security bind gate |
| 12.4 Storage/log lifecycle | ✅ dry-run/Trash/LogTrash tools prepared | 🟡 04:23 live DRY-RUN CAPTURED, 4/4 backup entries protected; 0 backup/log candidates, reclaim 0, disk 364.82 GiB free. No Apply needed based on this snapshot; lifecycle policy approval still pending |
| 12.5 Security | ✅ source/SBOM/CI and runtime audit tool prepared | 🟡 04:23 runtime audit CAPTURED_FOR_REVIEW; GSC bind reported loopback, 7 firewall Allow rules listed, **TCP listener inventory inconclusive**. ACL/firewall rule scope and backend binds require review; no security PASS claimed |
| 12.6 Trusted release | ✅ fail-closed closure gate + final Stable release workflow + reproducibility/provenance prepared | ⏳ final Stable promotion after every live gate |
| 12.7 Offline/cache | ✅ known-good cache audit/build and recovery kit tooling prepared | ✅ Build PASS (03:45 KST) and 04:23 READ-ONLY Audit CAPTURED (84 cache artifacts); ⏳ actual offline startup/recovery E2E still pending |
| 12.8 DR | ✅ synthetic DR + Recovery Kit **PASS** — run `37670892599` | production files untouched; synthetic/non-production scope satisfied |
| 12.9 UX cleanup | ✅ obsolete installer 4.3.0 README payload retired; installer baseline = 4.3.8/+117; System CI `37669908817` PASS | ⏳ only runtime UI observations if any |
| 12.10 Final verifier | ✅ canonical read-only verifier + fixed TCP diagnostic (`f41b107b` Safety CI PASS) | ❌ 04:23 live verifier: 18 PASS / 0 WARN / 1 FAIL (`backend_ports_private`, `tcp_inventory=unavailable`, online 25570/25571/25573 lack listener proof); no gate bypass |
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
