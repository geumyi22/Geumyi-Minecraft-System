# GSC Velocity lifecycle control — Phase B safety contract (2026-10-17)

**Status:** DESIGN + READ-ONLY PREFLIGHT. Not runnable lifecycle controls; not a production release.

## Actual server evidence and limitations

Operator-provided redacted inventory collected **2026-10-17 21:06 KST**:
- Day10 Velocity scheduled tasks for **wild / playground / other** present, matching expected baseline and `Running`.
- **Three parent-child JVM pairs** and three unique UDP-owning Velocity child process candidates on UDP 19132 / 19133 / 19134.
- `Get-NetTCPConnection` returned no TCP rows on 25565 / 25566 / 25567. This is **incomplete Windows provider telemetry**, not proof that TCP was down or ports collided.
- Subsequent screenshot of the currently installed GSC **Java / Bedrock 공개 포트 응답** pane independently reported Java TCP responses on 25565 / 25566 / 25567 **and** Bedrock RakNet responses on 19132 / 19133 / 19134. **6/6 port-level application probes PASS in the operator screenshot.**
- This is not proof of **real client Lobby login/transfer, effective backend privacy, which scheduled task owns each child JVM, player count, graceful shutdown bridge capability or post-change safety**. No restart was executed.

## Phase B read-only control preflight

`GET /api/v4/velocity/preflight?id={wild|playground|other}&action={start|stop|restart}` is an authenticated GSC Host API. It checks the **same fixed three task/process candidates** used in Phase A and independently performs loopback Java TCP responsiveness plus Bedrock RakNet ping on the target's fixed published ports. Only the exact nine target/action combinations are valid; invalid selectors are rejected with 400 and non-GET methods with 405.

Response: `schema=1`, `read_only=true`, `decision="blocked"`, `safe_to_execute=false`, explicit blocker codes and observed read-only evidence. **There is no POST start/stop/restart endpoint, no token or override to elevate the result, and the false/blocked outcome is unconditionally enforced by code, including on all-healthy fixtures.** UI buttons are clearly labeled as preflight checks, not lifecycle operations.

Blocked reasons and the controls needed to clear them in a **future separately approved implementation**:

| Control | Requirements before an actual request can ever be considered |
| --- | --- |
| All | Operator authorization for the named proxy and named operation; complete process/task identity; on-host scoped audit and rollback procedure; verified client E2E when required |
| Start | Existing target's **full process family absence** proven, zero or verified-free ports via authoritative independent checks, task definition fingerprint pinned and no stale copies; no automatic start of intentionally stopped Paper Other backend |
| Stop | Authenticated **graceful** Velocity shutdown routed only to intended JVM; player quiescence validated and logged, Geyser/RakNet receives shutdown or clients have disconnected, task restart policy understood |
| Restart | All stop gates, old parent+child gone and public endpoints down, then one approved start, new task-linked parent+child and TCP/RakNet recovered; halt and alert on intermediate failure; other proxy siblings unchanged |

**Never** call `Stop-Process -Force`, `taskkill /F` or `Stop-ScheduledTask` under a "normal stop" label, as the original Day10 cutover helper was a different, explicitly destructive operator operation.

## Safe remote control architecture (not implemented here)

Use a separate **Velocity plugin** loaded under each proxy, exposing a hardened *local-only* control channel to GSC Host with this initial scope:
1. Authenticated, request-bound command for `status` (PID lineage, logical proxy ID, player count), with explicit privacy; no raw console arbitrary-command relay.
2. Replay-resistant `prepare-shutdown` bound to target, operation nonce, operator/session authorization, zero-player gate, timeout and acknowledged transfer/disconnect behavior.
3. `confirm-shutdown` requires a freshly issued one-time capability, then invokes Velocity's supported `ProxyServer.shutdown()`; must not touch sibling instances or Paper backends.
4. GSC verifies target parent+child process departure plus matching ports' responsiveness transition and checks task scheduler hasn't spawned a replacement. On failure it **halts and never guesses/kills by PID**.
5. Start control, if separately approved, invokes only the expected task after trusted identity/port absence checks; reread fingerprint on each operation and validate Java+RakNet + real client smoke after restart.
6. Any management transport must bind to loopback/named pipe and use OS-protected access credentials per proxy. No forwarding secrets, Floodgate keys, Geyser pack data or GSC access tokens should be embedded in repos, logs, UI or shared JSON.

Windows Scheduled Tasks created Day10 run as SYSTEM and specify `RestartCount 999`; **do not assume** that `ProxyServer.shutdown()` yields a durable stopped state. The watchdog/restart interaction needs isolated synthetic Windows tests and operator-controlled sandbox trials before touching the real tasks.

## Test matrix, release hold

- [x] Prior Phase A read-only actual server process + UDP association sample
- [x] Operator screenshot: all 3 Java public ports and all 3 Bedrock RakNet public ports responded
- [x] Phase A six-process mock fixture and Go source checks on prior exact-head CI
- [ ] Latest Phase B exact-head Go tests: all 3 targets × 3 actions × healthy/unhealthy, invalid endpoints, no HTTP mutation
- [ ] Actual installed GSC Phase B UI smoke (requires a separate deployment approval; **not** performed)
- [ ] Plugin IPC security threat-model and independent review
- [ ] Offline disposable VM integration: SYSTEM task ownership, three JVM pairs, graceful quit, auto-restart interaction
- [ ] Zero-player and player-present controlled shutdown tests
- [ ] Approved on-host rollout and player Java/Bedrock E2E retest

Release labels and CI green do **not** clear strict Stable security gates. Keep PR in Draft and preserve `main`, all existing releases, real Velocity/Paper processes, worlds and backups.
