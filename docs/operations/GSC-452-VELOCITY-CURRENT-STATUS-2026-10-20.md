# GSC 4.5.2 Velocity — current implementation and operator handoff

> **Snapshot: 2026-10-20 KST.** This is the current post-Day-12 development record, not a change to the canonical Day 1–12 completion history. All changes in this document are Draft PR #57 only, not deployed.

## Version and release truth

| Component | Status | Evidence / restrictions |
|---|---|---|
| GSC 4.5.1 + GSCM 1.5.1+151 | Latest GitHub published manual-install Stable | [Published release](https://github.com/geumyi22/Geumyi-Minecraft-System/releases/tag/system-2026.10.11-stable-gsc451-gscm151). Strict signed automatic Stable deployment remains a separate blocked gate. |
| GSC 4.5.2 Velocity managed | **Draft Canary source + isolated CI binary only** | [PR #57](https://github.com/geumyi22/Geumyi-Minecraft-System/pull/57). No installed 4.5.2 Host, production merge, release, or cutover is established. |
| Velocity Java plugin / status-only IPC | Separate **inert experimental alternative**, not the current lifecycle implementation | [PR #58](https://github.com/geumyi22/Geumyi-Minecraft-System/pull/58). Its Java plugin does not stop/restart JVMs or execute real player admission changes. |
| GSC release-channel policy | Draft specification | [PR #54](https://github.com/geumyi22/Geumyi-Minecraft-System/pull/54). Do not label proposed release-channel UX as deployed. |

## Exact production evidence provided by operator

1. Sanitized PRECHECK reported all three Day10 Windows tasks **Running**, Java TCP / Bedrock UDP listener ports **occupied**, owner marker **absent**; migration readiness false for wild/playground/other. This indicates legacy Scheduler-owned JVMs are active, not GSC-owned launchers.
2. Sanitized real-host launch audit reported for **all three**: direct `java.exe` execution, existing fixed ProgramData FourServer working directories, existing Java executable and `velocity.jar`, pinned official 4.2.0 CI artifact SHA match, `RestartOnFailure.Count=999` policy. Existing Java console STDIN control remains **NOT PROVEN**.
3. Operator ran elevated snapshot-only kit. Output contained `operation=SNAPSHOT_ONLY`, `task_mutations=0`, `launched_jvms=0`, and `saved_targets=[wild,playground,other]`, with all original task XML and derived launcher manifests saved in protected operator-local storage. **Snapshot completed. Do not request the operator to repeat it or upload private XML.**
4. Operator approved a scoped temporary player interruption and, if graceful console control is unavailable, immediate stop of **only** the three exact task-owned Velocity proxy instances as part of a verified rollback-capable maintenance. Approval does **not** establish that those instances have already stopped. Paper servers, worlds, Geyser/Floodgate secrets, other tasks, current Stable and backups are outside the change scope.
5. **Operator confirmed Canary staging** by submitting `CANARY_STAGED_NO_INSTALL`: all three original tasks preserved, original live GSC Host executable copied to protected private CanaryStaging and SHA-256 verified against the live service, staged 4.5.2 Canary binary SHA-256 verified; service restart=false, scheduled task changes=false, Java changes=false. **This is not installation or activation.**

## Repository and CI evidence

| Verified in isolated GitHub runners | Result / limit |
|---|---|
| Go host APIs and Race tests | PR #57 [System CI 39441217776](https://github.com/geumyi22/Geumyi-Minecraft-System/actions/runs/39441217776) succeeded, as did associated Day 11/12 workflows at head `01e5c989`. This is **CI evidence**, not live server proof. |
| Real official Velocity 4.2.0 JAR managed by GSC-owned process | GitHub disposable Windows start → console `shutdown` → restart → stop passed; does not demonstrate actual live Java/Bedrock joins or foreign task-process takeover. |
| Task Scheduler cutover/rollback | CI-owned, no-trigger fake Windows task: original XML and manifest snapshot → Disabled → Ready → cleanup passed; no live task was changed. |
| GSC Canary Host EXE | Version-stamped 4.5.2-canary executable, SHA256SUMS, non-destructive `--day10-selftest`, **uninstalled artifact**. This is not a Stable setup installer. |
| Velocity action authorization | Require explicit local host API token even when `AllowLoopbackNoAuth` is enabled; device/remote/no-token action denied. Actual production principal/installation remains untested. |

## State of functional implementation

- The GSC Host Draft exposes authenticated `GET /api/v1/velocity/tasks` and `GET /api/v1/velocity/managed/status`; the console-start/stop/restart `POST /api/v1/velocity/managed/action` is **off by default** and requires the gated migration and protected local evidence. The dashboard provides disabled-by-default control buttons.
- A GSC-owned JVM receives the official `shutdown` command via its **own** standard input. The existing task-owned JVM is **not adopted**. The controller will not force-kill a still-running managed JVM after a failed stop.
- Task migration requires a verified matching private original XML receipt and manifest, original Scheduler task Disabled, and safe port state. Durable owner-generation marker blocks silent duplicate launch after a GSC Host restart; it is intentionally fail-closed, not proof that unattended orphan recovery is complete.
- The admin Snapshot/Cutover/Rollback kit has synthetic and disposable Windows CI tests; **task rollback re-enables original Scheduled Task but does not automatically restart the Java JVM**. Live service restart, full player routing and unattended recovery are unverified.

## Next decision gate — **not authorized to blindly execute**

1. **Stage-only is complete.** Next run only the dedicated non-mutating Windows GSC Host service/backup/rollback preflight to recheck service command, process path, protected private original backup, candidate SHA, localhost health, legacy proxy task states and owner-marker absence. Do not repeat snapshot/stage. A green preflight is not authorization to install.
2. Finalize and separately test a **GSC service installation/recovery** procedure with explicit service restart and rollback evidence, then confirm the Canary routes remain locked before cutover. Do not simply run a second Host beside the live Host.
3. Cold migrate **one Velocity proxy at a time** (wild → playground → other) only after service fallback and launch preflight are proven. If a task-owned JVM cannot be shutdown gracefully, the user-approved immediate task stop may interrupt players. Verify old JVM exit and both port families, then perform one-target protected cutover, start the GSC-owned JVM, check real Java+Bedrock joins and forwarding; rollback if any gate fails.
4. Validate behavior during a GSC Host restart / orphaned Java generation. Do not clear a stale marker, guess PID identity or re-enable old task while an owned JVM might remain. Automation cannot be called production-ready without this proof.
5. Only after live checks, separately decide whether to promote Draft Canary to Beta/Stable. Do not amend existing Stable release tags or auto-deployment metadata based on CI-only success.

## Source of truth and related documents

- [Detailed technical cutover runbook](GSC-VELOCITY-DIRECT-OWNERSHIP-CUTOVER-2026-10-19.md): chronology and operator safety details; early sections are historical proposals and are superseded by this status sheet where inconsistent.
- [Open PR triage by topic](PR-TRIAGE-2026-10-20.md): #47–#58 review grouping without deletion or premature merge.
- [Day 1–12 canonical closure](../../DAY-TIMELINE.md) and [2026-10-11 closeout](../../PROJECT-CLOSEOUT-2026-10-11.md) remain historical truths, not a statement that this new Canary is complete.

**Safety:** no release, merge, live service restart, live task stop, Paper/Velocity process action, world edit, backup deletion or file permission change should be inferred from this document.
