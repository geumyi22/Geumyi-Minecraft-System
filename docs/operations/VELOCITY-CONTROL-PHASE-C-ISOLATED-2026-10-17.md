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

Negative regression fixtures include mismatched target directory, PowerShell/foreign Java action, additional COM action, wrong principal, missing/malformed restart count, empty input, unknown proxy ID, fake XML namespace and oversized payload. This is an isolated verification of guard logic and **does not read the user's Windows Task Scheduler**.

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
