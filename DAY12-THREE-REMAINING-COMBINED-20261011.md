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
