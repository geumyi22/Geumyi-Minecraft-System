# Day 12.11 #12 — real disposable Paper crash-recovery evidence review (2026-10-11)

## Overall result: PARTIAL REAL DISPOSABLE PROOF; CI GATE NOT GREEN

All process terminations described here happened **only inside temporary GitHub-hosted Windows runners** using one verified pinned public Paper 26.3 archive and a separately built GSC Host 4.3.8. No command was run on the operator's server; no private worlds, ports, Golden backups, firewall/ACL, production GSC services or plugins were modified.

### First run — <https://github.com/geumyi22/Geumyi-Minecraft-System/actions/runs/38068566612>

The runtime script printed `Disposable result: DISPOSABLE_REAL_GSC_PAPER_CRASH_RECOVERY_PASS` after it had established the test-only Paper owner/PID, terminated the test-only Java process, observed real GSC `RECOVERING`, and observed a new test-only Paper listener owned by a different PID after watchdog recovery. **However, the GitHub Actions workflow FAILED** because the script's former final exit-code check recognized only the older offline-source success label, not the new crash-recovery success label. This is evidence of the observed test sequence but **not a green whole-workflow proof**.

The exit-code handling was fixed in source commit `387017ec74f91974e504911f2ef1c99d04b6c5cc`.

### Second run — <https://github.com/geumyi22/Geumyi-Minecraft-System/actions/runs/38068765166>

**FAILED before fault injection.** The pinned Paper 26.3 server bound its TCP port while the world was still initializing. The harness immediately sent an initial prewarm `stop` command; Paper logged a server initialization `NullPointerException` for `/stop`. The initial process then did not exit in the bounded graceful-stop interval and the script reported `INITIAL_PAPER_NOT_GRACEFULLY_STOPPED`. This does **not** establish a failed GSC watchdog or production instability; that later crash-recovery section was not reached in this run.

### Engineering status and acceptance

- **Observed:** Actual, isolated real GSC + Paper process crash/recovery behavior on one runner; not merely a Go state-machine fixture.
- **Not yet qualified:** Repeatable full workflow **SUCCESS** of that new #12 fault-injection suite.
- **Next non-production engineering fix:** Wait for Paper's completed `Done (...s)` startup log (not just TCP listener opened) before sending the prewarm graceful stop. Verify on disposable Windows CI, and only then update the scoped evidence ledger. Do not restart, stop, kill or alter the operator's Paper server to make #12 green.
- **#17:** Canary policy and temporary JAR transaction rollback tests are already covered by disposable Go and separate GSC 4.3.9 RC staging source; a production signed Canary apply/rollback E2E has not been run.
- **Release:** strict 12.5/12.7/12.10/12.11/12.12 instrumented Stable prerequisites remain unchanged. `FINAL-RELEASE-GATES.json` must continue to block signed Stable and maintenance promotion.

The existing Playground/Bedrock/Java player-facing smoke acceptances are not invalidated and must not be repeated due only to test-runner issues.

## 2026-10-11 follow-up — disposable Windows CI is now GREEN (supersedes earlier CI status)

**PASS in isolated GitHub Windows runner scope:** [run 38075813601](https://github.com/geumyi22/Geumyi-Minecraft-System/actions/runs/38075813601), commit `f5e8963967e40f58cb98942b9785b5cebbfdfe70`, job `disposable-paper-crash-and-watchdog` completed SUCCESS. The test log explicitly contains `Disposable result: DISPOSABLE_REAL_GSC_PAPER_CRASH_RECOVERY_PASS`; the workflow subsequently checked the redacted report's initial Paper ready/graceful stop, GSC start and update-source outage, pinned JAR hash, exact disposable Paper PID, forced termination **in runner only**, observed real GSC RECOVERING and a newly spawned Paper PID, and continued without error. Artifact: `day12-phase11-disposable-gsc-paper-crash-recovery-result` ID `11678299981`.

**Engineering fix:** The CI harness now waits for the actual Paper `Done (...s)! For help, type "help"` log and six seconds of stable listening before the prewarm `stop` request. It allows one bounded second graceful stop request if needed, then checks zero exit code and a graceful shutdown log. This resolves the earlier race between port bind and world initialization; it does not alter GSC Host/Paper production code or weaken pass requirements.

**Scope:** Physical test-only GSC/Paper processes in GitHub runner, not operator host. The operator's production server was **never** crash-injected, restarted or modified. Mark **12.11 #12 DISPOSABLE CI E2E PASS**, but **not** production real-host crash-recovery PASS and **not** global 12.11/12.13 closure. #17 signed Canary/rollback and other mandatory release gates remain open. The prior historical failure discussion above is retained for audit, but its `CI GATE NOT GREEN` wording is superseded by this newer successful run.
