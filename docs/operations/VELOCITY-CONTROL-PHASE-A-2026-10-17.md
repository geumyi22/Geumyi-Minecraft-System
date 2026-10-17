# GSC Velocity Management — Phase A: Read-only inventory (2026-10-17)

**Scope:** Windows GSC Host status inspection and desktop Servers UI only. **No server, proxy, Task Scheduler, world, backup, firewall, service, or GSC installation changed.** Code is on a Draft review branch, not on production `main`.

## Verified existing topology (historical code)

The Day10 installer registered **three Scheduled Tasks** as SYSTEM:
- `Geumyi Day10 Velocity wild` → TCP 25565 / Bedrock UDP 19132
- `Geumyi Day10 Velocity playground` → TCP 25566 / Bedrock UDP 19133
- `Geumyi Day10 Velocity other` → TCP 25567 / Bedrock UDP 19134

Each is configured to run Java with `-Xms256M -Xmx512M -jar velocity.jar` from `%ProgramData%\GeumyiServerCenter\Network\FourServer\<id>`. Real on-host paths and actual task settings must be independently verified again before any action path is enabled.

## Phase A implementation

- `GET /api/v4/velocity/status` is **authenticated** with the same Host middleware as other GSC protected API routes.
- Windows-only, PowerShell 5.1 status script compiled into the Host executable using `go:embed`; no downloaded or writable temp scripts.
- Fixed, allowlisted three task IDs and port pairs; no user-controlled task names or PowerShell argument interpolation.
- Validate task presence, root path, SYSTEM principal, Java executable name, jar argument and working directory against expected Day10 shape. Report only booleans, task state and fixed ports; do not expose command lines, raw PIDs, tokens, paths or floodgate keys.
- Inspect bound TCP and UDP owning PID sets. **Even matching PIDs do not prove that they belong to the expected Velocity instance**, nor that Geyser responds to RakNet, nor that a player can join Lobby. The UI explicitly labels this `ports_ready_owner_unverified`.
- Unknown, missing or duplicate tasks, missing/partially owned ports and read errors **fail closed** into warning/unknown. No restart or self-healing side effects.
- `POST/PUT/DELETE` returns HTTP 405. The Servers page only provides a **read-only refresh**.
- Separate Host tests enforce exact three target IDs and fixed TCP/UDP mappings and forbid mutation methods.

## Why Stop / Restart are not exposed yet

The original Day10 installer helper uses `Stop-Process -Force` for its one-time bootstrap/cutover. Using it as GSC's ordinary “normal stop” would disconnect players and risk inconsistency. Scheduled Task `Stop-ScheduledTask` is also not established as a graceful Velocity shutdown API; the task is configured with extensive automatic retries/restarts. Velocity has no proven managed, authenticated stdin or equivalent graceful control channel in the current GSC code.

A reliable control implementation must first establish:

1. **Identity**: each task's exact action, expected runtime directory, actual Java process lineage, TCP/UDP socket owning PID and authoritative task instance must be attributable without guesswork; fail closed on ambiguity.
2. **Normal stop**: an authenticated, local-only, bounded graceful Velocity shutdown mechanism (such as a separately verified Velocity plugin bridge) with audit and countdown; no forced kill under a “normal” label.
3. **Start**: require both public ports free, no duplicate task/Java processes, correct selected task, and host permission; start only one named task without touching other instances.
4. **Restart**: normal stop health gate → both Java TCP and Bedrock UDP close → safe start → Java and real RakNet health pass. Failure preserves other proxies and reports a recoverable state.
5. **Operational protection**: player-aware warnings, in-flight operation lock, exception handling and bounded timeout, exact task/PID scoping, backups/rollback where relevant, and an operator-confirmed live test. Never auto-start intentionally OFFLINE Other backend or change Paper.
6. **Security**: authenticated Host routes; explicit action confirmation and role policy; no proxy secrets or reusable token exposed; 403/409 on unapproved actions.

## Validation / blockers

- [ ] Go Host + Windows build tests (from Draft PR CI)
- [ ] Windows PowerShell 5.1 non-production task-mock/synthetic smoke
- [ ] Read-only actual on-host three-task/ports capture
- [ ] GSC desktop UI smoke for read-only states
- [ ] Independent review of task-identity assumptions
- [ ] Only after a safe, tested graceful shutdown path exists: implement explicit control actions in a **separate** PR

**Do not merge or deploy until the above code-review and test conditions are met.** This is not a Day12 production-security-gate PASS or complete start/stop/restart solution.
