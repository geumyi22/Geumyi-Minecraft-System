# Phase C — Isolated Velocity Lifecycle and Local Authentication Prototype

**Date:** 2026-10-17. **Status:** offline-only library and unit tests; NO plugin, NO GSC controller route, NO live control.

## Relationship to live Geumyi servers

- The user-reported host inventory confirms exactly three Day10 scheduled tasks, 3 parent/child JVM pairs, 3 UDP child owners. An independent GSC screenshot confirms all **3 Java TCP + 3 Bedrock RakNet** public endpoints replied (6/6). Missing Windows `Get-NetTCPConnection` data must **not** be interpreted as outage, port free, or process stopped.
- Draft [PR #55](https://github.com/geumyi22/Geumyi-Minecraft-System/pull/55) implements a **read-only** preflight, always `safe_to_execute=false`. This phase intentionally **does not integrate with or change PR #55**; merging this prototype must never unlock it.
- Three known Velocity proxies: wild (TCP 25565 / UDP 19132), playground (25566/19133), other (25567/19134). Paper backends remain separate; never auto-start the intentionally stopped Other Paper server.
- The existing Windows Scheduled Tasks create JVM parent/child relationships and have aggressive restart settings. A successful Velocity shutdown request may immediately relaunch under task supervision. That behavior must be proven in an isolated VM before live operations.

## Added code — no OS effects

1. `GSC/ServerCenter/internal/velocitylifecycle/lifecycle.go`
   - Only three allowlisted proxy IDs and three actions (start, stop, restart).
   - Deterministic, in-memory simulation stages `preflight` → `await_graceful_shutdown` (**ACK only**) → `await_process_stopped` (**old JVM and ports actually gone**) → `await_start_receipt` (**scheduler ACK only**) → `await_new_process_healthy` (**new pair and Java/RakNet actually responding**) → `simulation_complete` or terminal `blocked`. Start/stop omit the irrelevant stages.
   - Guards: named target, operator approval and maintenance window, authentic task fingerprint / process lineage, safe scheduled-task restart policy, no duplicate JVM family, unaffected sibling proxies, audit availability, zero verified players for stop/restart, authenticated graceful shutdown bridge, old process generation gone, **independently proven** free Java TCP + Bedrock UDP ports, a distinct newly attested process pair, and new Java TCP / real RakNet replies.
   - Every stage is order-bound to a simulation ticket, sequence and deadline. Missing, out-of-order or conflicting evidence blocks permanently. **Shutdown ACK never counts as JVM exit, and start receipt never counts as Java/RakNet readiness.**
   - `LiveAuthorized` is **always false**, even for complete simulations. There is no command execution, HTTP route, PowerShell, Scheduled Task, file, network or server mutation.
2. `GSC/ServerCenter/internal/velocitybridge/auth.go`
   - Independent versioned HMAC-SHA256 envelope prototype for a **future loopback/named-pipe bridge**: exact proxy, exact operation, process generation, random nonce, issued time, <=20 s lifetime.
   - Minimum 32-byte key provided in memory by the caller; no keys generated into repo/config or printed.
   - Fixed-length constant-time MAC comparison, short clock skew, one-time nonce use with a mutex-protected bounded replay ledger that **rejects** when full.
   - Supported *message vocabulary only*: status / prepare_shutdown / confirm_shutdown. **No listener or Velocity shutdown operation exists**.
   - This HMAC prototype **does not substitute for user authorization, local IPC peer attestation, player-count proofs or task-owner verification.** A future secure broker must source keys from protected per-proxy OS secrets and prove peer identity before accepting messages.
3. Automated tests: nine target/action happy-path simulations always `LiveAuthorized=false`; missing approval, player present, unsafe scheduler, wrong task, sibling drift, missing old process, empty Windows port provider, same-generation restarts, unhealthy Java/RakNet, timeout, replay and forged HMAC/cross-proxy scopes reject; concurrent replays accept exactly once.

## Phase C supplementary synthetic Windows Task Scheduler definition assessment

Added `internal/velocitylifecycle/scheduler_policy.go` and its table-driven tests. The pure Go parser accepts at most 64 KiB of **caller-supplied synthetic XML bytes** in the official Windows Task Scheduler namespace, with no `os`, `os/exec`, Task Scheduler APIs, process enumeration, file reads, filesystem writes or network calls.

The parser checks only structural assertions: exact `wild|playground|other` proxy target, one Windows `Exec` action with `java.exe`, relative `-jar velocity.jar` and matching directory suffix; SYSTEM/service-account principal; `RestartOnFailure.Count`, including an explicit **999 attempts** hazard. It identifies unknown/ambiguous/malformed definitions as unverified. Every resulting `safe_to_start`, `safe_to_stop`, and `safe_to_restart` field is **unconditionally false**. A task XML definition cannot prove that the task spawned a particular live JVM, a player's absence, a graceful plugin control bridge, that a child exited, or that a stop will persist despite automatic restart.

Negative regression fixtures include mismatched target directory, PowerShell/foreign Java action, additional COM action, wrong principal, missing/malformed restart count, empty input, unknown proxy ID, fake XML namespace and oversized payload. Additional adversarial fixtures reject UNC and relative executable paths, arbitrary directory-suffix matches, duplicate `-jar` switches and unsafe `MultipleInstancesPolicy` modes (`Parallel`, `StopExisting`, or missing instead of `IgnoreNew`). These are strictly in-memory classifications: a correctly shaped task XML still provides **no proof that a particular task actually owns a live Velocity JVM**. This is an isolated verification of guard logic and **does not read the user's Windows Task Scheduler**.

## Phase C supplementary three-proxy evidence fusion (simulation only)

Added `internal/velocitylifecycle/fleet_preflight.go` and table-driven Go tests. They accept **only caller-provided synthetic observations** and do not access the Windows process table, task scheduler, network, filesystem, world or GSC APIs.

The checker expects precisely three fresh, distinct `wild`, `playground` and `other` snapshots, with expected endpoint pairs `25565/19132`, `25566/19133` and `25567/19134`. Each supplied snapshot must identify a consistent parent/child relationship, independent task-to-parent correlation flag, UDP ownership by the child, independently responding Java server-list status and Bedrock RakNet PONG. If a Windows TCP socket inventory is positively present, its owner must match the target child JVM; if that inventory is *missing*, the checker distinguishes a **telemetry gap** from an application outage only when an independent Java application response exists. This preserves the real operator's earlier 6/6 Java/Bedrock endpoint observations without reinterpreting missing `Get-NetTCPConnection` entries as proof that a port is free.

Reference artifact identity is restricted to PaperMC's **Velocity 4.2.0 Build 30** SHA-256 value recorded earlier, not the latest mutable version. Cross-proxy JVM PID collisions (including parent-to-other-child collisions), wrong ports, wrong UDP/TCP owners, task definition changes, missing independent task/PID attestation, missing Java or RakNet replies, stale or future timestamps, duplicate/missing/unknown proxies and JAR hash drift all fail closed. Raw PIDs are omitted from diagnostic results and are explicitly excluded from the snapshot's JSON representation.

**Critical trust boundary:** even when all *synthetic* checks are coherent, the result remains `source_verified=false` and `safe_to_execute=false`. A caller-supplied PID and a copied SHA are not provenance proofs. This policy is NOT wired to a production controller, cannot authenticate a Windows task, and cannot issue any task or Velocity operation. It also has no player/session authorization, maintenance-window authorization, peer identity or operator grants. The corresponding Go tests exercise valid correlation and adversarial input; they are not live preflight evidence.

## Required bridge-to-runtime architecture before any future operational attempt

1. **Immutable operator authorization:** verify a locally authenticated GSC operator with an explicit per-proxy action, short-lived maintenance window, one-time challenge and action confirmation; no unattended remote kill capability.
2. **OS-authenticated local peer:** constrain to a Windows named pipe with an allowlisted SID/ACL or equivalent OS-backed peer identity. Bind the per-proxy session to a fresh child JVM generation; loopback TCP alone does not prove peer identity.
3. **Controlled secret management:** independent random per-proxy HMAC keys stored outside repo and protected by OS ACL/DPAPI, expiry/rotation and replay prevention across bridge restarts. Never include a forwarding secret or Floodgate key in this channel.
4. **Player-aware lifecycle:** prove player count exactly zero immediately before graceful shutdown; reject if clients appear, authentication is uncertain, or requests race with generation changes. Ensure warning/countdown policy is operator-approved.
5. **Verified scheduler semantics:** correlate the exact Day10 Windows Task Scheduler instance with parent and child process tokens, verify restart-on-failure policy and explicit stop suppression, then independently prove both process absence and port release. A plugin shutdown ACK is not proof of process exit.
6. **Post-start independent checks:** verify genuinely new JVM parent/child generation plus Java status and RakNet packets for the correct proxy without interpreting missing TCP provider rows as a healthy or stopped process; test remaining two sibling proxy generations unchanged.
7. **Disposable Windows VM rehearsal:** test real Task Scheduler auto-restart races, orphaned child JVMs, wrong owners, slow startup, player-present declines, expired requests, rollback and crash recovery before any live maintenance. No real test data or backed-up worlds may be mutated as a shortcut.

Until these have independently verifiable implementations and security review, **no Canary/Stable release may advertise functional Velocity stop/restart support**. A green isolated simulation is not an OS operation permit.

## Full control still blocked — Phase D prerequisites

- [ ] Independently reviewed plugin source compatible with **exact installed Velocity version**; no broad console command relay. Official Velocity plugin API supports `ProxyServer.shutdown()`, but no such plugin is built or installed here.
- [ ] Restricted local-only GSC↔Velocity transport with independently authenticated process identity, separately protected credentials per proxy, OS-level ACL, rate limiting, full audit and replay controls.
- [ ] Real task/action hash, process-generation attestation from the Windows scheduler, and unambiguous parent/child ownership. Port responders do not prove PID identity.
- [ ] Safe, bounded, graceful plugin shutdown with zero-player requirements, warning countdown, task scheduler restart-policy handling and no PID `Force` fallback.
- [ ] Safe start only after verifiable absence of prior JVM family and independent TCP+UDP port availability. Flaky provider-empty results are not positive proof.
- [ ] Test in disposable Windows VM with a **synthetic** SYSTEM task and mock Java process, including expected task auto-restart, child orphan and partial-rollback cases. Never run lifecycle scripts against real tasks as a shortcut.
- [ ] Controlled operator-maintenance-window live tests, with Paper worlds and backups intact, real Java/Bedrock client E2E and possible rollback.
- [ ] Independent review and stricter Stable release gates from Day12. Production version promotion is separately blocked.

## CI and acceptance

`go test ./...` from `GSC/ServerCenter` exercises both packages under the existing **System CI** (Windows). The new source files depend only on the Go standard library. **CI green is synthetic source evidence only**, not operational authorization.

Do not merge into production or expose live Velocity lifecycle POST endpoints solely because these fixtures pass. Keep [issue #56](https://github.com/geumyi22/Geumyi-Minecraft-System/issues/56) open until Phase D gates are independently satisfied.
