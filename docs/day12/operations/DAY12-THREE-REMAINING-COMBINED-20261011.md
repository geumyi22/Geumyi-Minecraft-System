# Day12.11 — 2 + 12 + 17 combined review (2026-10-11 KST)

**One operator host action** after the GitHub workflow passes: download **Geumyi-Day12-Three-Remaining-OneClick-READ-ONLY** artifact, unzip the outer ZIP (which contains the kit ZIP), extract the inner kit ZIP, run `Start_Day12_Three_Remaining_READ_ONLY.cmd` on **SERVER PC** only, and share **ONLY** the desktop `Geumyi-Day12-Three-Tests/Day12-2-12-17-SHARE-SUMMARY-*.json`.

## Exact one-session scope

| List number | Test | Where checked | Completion meaning |
|---|---|---|---|
| 2 | GSC Host + Velocity parent-child + UDP ownership + four Paper-JAR candidates | Actual server PC, **READ ONLY** | `PASS_HOST_PROCESS_CENSUS_SCOPED` when all observable identities align; `REVIEW_REQUIRED` if missing/ambiguous |
| 12 | Unexpected loss → RECOVERING | **GitHub disposable Go test** `TestDeriveServerStateBasic` | State-machine decision validated; **an actual child process crash and automatic restart was NOT executed** |
| 17 | Update Dry-run, Canary policy and Rollback | **GitHub disposable Go tests** `TestDay11UpdateDryRunNeverInstallsOrRestarts`, `TestDay11CanaryTargetPolicyIsPolicyOnlyAndRestorable`, `TestDay11CanaryPromotionRequiresReleaseHealth`, `TestDay9TransactionFailureInjectionRestoresWholeGroup`, `TestDay9InterruptedAppliedTransactionRollsBackAndRejectsRelease` | Real temporary test files modified and restored inside disposable Go temp directory, policies/dry-run tested. **NOT** a live signed release/apply/canary and world rollback |

No command in the Windows operator kit executes a service stop, kill, start, restart, world restore, update apply, firewall/ACL change or port bind. The script reads Win32_Process (raw process command lines **memory only**, never reported), reads three Get-NetUDPEndpoint owner values **memory only**, and checks the existing GSC service status. JSON contains only aggregate counts/boolean checks and no PIDs, paths, full command lines or player names.

### CI and real-host distinctions

- A CI PASS means case 12 **logical recovery-state** and case 17 **disposable transaction rollback** source tests ran and passed, not a production runtime failure simulation.
- The host CMD only verifies **2**, subject to actual OS/CIM and UDP visibility. If 12 or 17 requires strict *real-world* E2E, they remain **OPEN** pending a separately authorized, disposable service/Paper + signed release simulation. **Do not force-kill any production process** to satisfy case 12.
- This package is a **single practical collection session**, not a fabricated 3/3 actual E2E result.
- This is unrelated to 12.7 offline startup, 12.10 strict native socket proof and 12.12 8-hour soak; all remain open and final Stable remains blocked.

CI link will appear under `Day12 Three Remaining Checks Bundle (2,12,17)` workflow. If workflow fails, do not use the kit.

## CI result: 2026-10-11

- GitHub workflow: [Day12 Three Remaining Checks Bundle (2,12,17) — SUCCESS](https://github.com/geumyi22/Geumyi-Minecraft-System/actions/runs/38063619014), verified Windows PowerShell 5.1 and focused real Go temporary-file tests.
- Artifact ID: `11673324745`, outer GitHub artifact contains a nested kit ZIP. No GSC/Velocity/Paper code/host configs were changed by this CI workflow.
- **Host #2 remains pending the operator's one-time read-only CMD and JSON**. 12/17 only source/staging Go integration tests, not an actual real process crash, live signed canary or production rollback. Never claim full 3/3 real E2E.

## Real operator evidence — 2026-10-11 00:29 KST

Submitted `Day12-2-12-17-SHARE-SUMMARY-20261011-002947.json` (`read_only=true`, `synthetic=false`), not committed to GitHub.

| Scope | Field | Result |
|---|---|---|
| #2 | GSC Host | 1 Running |
| #2 | Velocity | 6 = 3 verified parent/child pairs |
| #2 | 19132/19133/19134 | All three UDP owners match correct Velocity child |
| #2 | Java/Paper process classification | 3 `paper*.jar` matches + 1 Java whose role **not recognized** |
| #2 | PID uniqueness | True for classified candidates; doesn't prove unclassified JVM role |
| #2 | Net outcome | **REVIEW_REQUIRED** — not proof of a broken fourth Paper instance |
| #12 | `production_crash_performed` | False; CI state machine only |
| #17 | `production_update_performed` | False; CI disposable transaction tests only |
| Release | `backend_ports_private`, Stable | UNCHANGED_FAIL, not allowed |

This run **does not** justify killing or restarting the unidentified process, changing GSC, or altering the canonical strict private-port gate. Focus only on a safe role classification if further proof is requested.
