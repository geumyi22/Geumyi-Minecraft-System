# Day 12.10 — approved single-backend graceful restart

**Operator instruction (2026-10-10):** routine single-server restarts and similar routine checks may proceed without repeated permission questions. The assistant cannot control the user's Windows host directly, so the operator must still execute a supplied file there. **This approval does not include force termination, world restore/data deletion, broad outage, Windows reboot, port/firewall/ACL/security policy changes or irreversible changes.**

## One selected target, not a fleet reboot

- **Playground only**: backend Java `25571`, RCON `25576`; Wild/Lobby/Other deliberately not touched.
- **Action**: GSC's official authenticated/local `/api/v1/servers/playground/actions` job with `action=restart`, `countdown_seconds=15` (one attempt). No `taskkill`, no PowerShell `Stop-Process`, no manual process-kill.
- **Run**: `tools/day12/Day12_Phase10_Scoped_Graceful_Restart.cmd` on Minecraft SERVER PC from the latest Operator Kit, using a normal user account with local GSC API access.
- **Report**: Desktop `Geumyi-Day12-Scoped-Restart/Day12-Scoped-Restart-*.json`. Send the new JSON to ChatGPT; no raw server logs, paths, passwords or backup contents.

## Safety guard — a missing precondition prevents mutation

1. GSC localhost version exactly **4.3.8**, 4-server fleet status available, and **Playground ONLINE**.
2. GSC global active control jobs **0**, no active/blocked update transaction in the target fleet snapshot.
3. Actual Minecraft status query must prove Playground **ONLINE and player count 0**. Missing/unavailable query is a **BLOCK**, not zero players.
4. At least one **PROTECTED, VERIFIED, FULL, non-Trashed** Playground Golden backup listed by GSC before restarting. The tool does not create, overwrite, delete or restore backup assets.
5. Repeat online player and active-job checks immediately before the **one** GSC job enqueue.
6. Wait boundedly for the GSC job state `completed`; then verify target returns ONLINE. Never automatically try a second restart on failure.
7. A **single** scoped post-restart Windows native TCP LISTENER observation for `25571` and `25576` may inform ownership/bind questions. Missing native rows are **INCONCLUSIVE**; any nonloopback row requires immediate review and no further operations. This **never automatically clears `backend_ports_private`** or changes Stable.

## Important caveats

- GSC has an existing prestart updater. **A regular restart can trigger that configured update policy**; this tool does not install updates by itself or change release policies. If the existing policy is unacceptable, do not run production restarts until it is reviewed.
- GSC's job `completed` means the job process completed; the script also performs a separate online check. A successful restart still does not prove every other Java/RCON listener is bound to loopback.
- Synthetic Windows CI checks accepted preflight, active jobs, player present and missing Golden failure cases **without contacting any GSC host**. CI success does **not** establish real-server E2E.
- **Stop and review**, rather than force stopping or starting repeatedly, if the script produces `BLOCKED_*`, `RESTART_JOB_*_REVIEW`, missing backup, auth/API error, or an unexpected update state.

## 2026-10-10 02:41 — real preflight blocked by omitted update flag

- Submitted Day12-Scoped-Restart-20261010-024155.json from the server PC: protected verified full Golden, Playground online, zero players and zero GSC control jobs passed; **no restart was accepted or performed**. BLOCKED_UPDATE_BLOCK_START is not proof of a real update block.
- GSC UpdateStatus.BlockStart is serialized with omitempty. Initial script treated a missing flag as true. Revised script interprets absent block_start as false only if updater status exists with known safe phase; explicit true, missing status, active update, no Golden, players and queued jobs still fail closed.
- Synthetic tests cover omitted and explicitly true flags, unsafe downloading, missing update status, and safe available phase. Re-download the current Operator Kit; do not execute the stale preflight again. One guarded graceful Playground restart remains the only planned action. If it cannot confirm safety, it exits without mutation.

## Result of the one authorized real-host restart (2026-10-10 02:47 KST)

- `Day12-Scoped-Restart-20261010-024734.json`: GSC Playground graceful restart accepted, **job completed**, server **ONLINE before and after**, verified protected Golden, zero players, zero jobs, updater phase `current`, `block_start=false`.
- A single native listener inventory was CAPTURED but returned **NOT_OBSERVED** for `25571` Java and `25576` RCON. Thus lifecycle PASS but **OS private bind proof still incomplete**. This result does not imply exposure or full security verification.
- **Stop here. Do not repeat the restart** without a new hypothesis or approved operational need. Preserve all protected Golden backups; 12.10 canonical FAIL and Stable hold remain. Follow `DAY12-PHASE10-SECURITY-DECISION-PACKET.md` for acceptable next proof/policy routes.

## Consequences and rollback

A successful Playground restart temporarily disconnects anyone there (the tool blocks if connected players are reported), and may run existing start-time plugin update policies. All other servers are intended to remain running. If restart health fails, retain the prior Golden backup and submit the JSON; do not perform automated restoration or another restart. Use GSC's existing controlled recovery/rollback path **only after** reviewing logs and backup health. The protected Golden remains immutable.

**Gate status: Day 12.10 OPEN.** This operator-approved routine restart is a bounded real-host source-of-truth experiment, not permission to alter security acceptance criteria. Day 12.11 live E2E, 12.12 soak, 12.13 Stable, and Day1–12 cleanup remain gated.
