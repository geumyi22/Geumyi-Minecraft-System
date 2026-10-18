# GSC Velocity Direct Ownership — Fast Critical Path (2026-10-19)

**Proposal, not an operator command. No production changes are authorized by this file.**

## Decision

Prefer **GSC-owned Velocity JVMs** over implementing a second independent privileged GSC↔Velocity shutdown controller for three task-launched proxies.

PaperMC Velocity already supports a **console-only** built-in `shutdown` command that gracefully shuts down a proxy and disconnects players. A GSC process that *owns the launched Java child's stdin pipe* can send that command, wait for exit, then start the next JVM from a verified fixed launch specification. This approach **does not require installing a new Velocity plugin or distributing cross-process HMAC secrets for lifecycle control**.

Official reference: https://docs.papermc.io/velocity/built-in-commands/#shutdown

## Existing operational constraints

- Three currently running Day10 Windows scheduled tasks named `Geumyi Day10 Velocity wild`, `... playground`, `... other`.
- Task startup is currently **external to GSC**; GSC does not own those old process handles or console standard input.
- Historical read-only reports show matching GSC host / task owner Windows SIDs, but **not** ownership of existing Java stdin/process.
- Existing Task Scheduler retry Count=999 and pinned original task definitions must remain unchanged until an explicitly approved cutover.
- **Do not** kill or adopt the existing proxy JVMs via PID guess, task name suffix, Java path or process tree. Do not launch duplicate JVMs into the same ports.
- Preserve production Velocity/Geyser/Floodgate JARs, keys, worlds, config and network behavior.

## Implemented on Draft PR #57

1. Authenticated `GET /api/v1/velocity/tasks` reads only the three fixed Scheduler task states on Windows. It never accepts POST, exposes SIDs/PIDs/commands/paths or claims task RUNNING means the Java/Bedrock proxy is healthy.
2. GSC dashboard renders these actual task states on a 15-second refresh in its new Velocity section. All stop/start/restart controls remain disabled until cutover.
3. `internal/velocitymanaged` holds a testable real process supervisor that launches an explicitly configured absolute executable without a shell, owns the child stdin and process handle, accepts ONLY the Velocity console `shutdown\n` graceful exit, blocks concurrent or duplicate starts, and starts a replacement JVM **only after exit confirmation**. There is no force-kill fallback. Denied operator/player-disconnect-consent/task-migration permits or timeouts leave the owned JVM untouched.
4. Go tests start only their own disposable Go test child, exercise actual stdin graceful stop, restart, duplicate-start, cross-target permit rejection and unresponsive-shutdown fallback. Real Velocity, Windows tasks, Paper servers, worlds and ports are untouched. System CI and race checks cover this package.

## Remaining engineering — no redundant host diagnosis

1. **Source-only integration:** add a GSC host-owned Velocity launcher manifest (versioned, canonical and locally protected), pinned `java.exe`/jar/config arguments, working-directory verification, port/duplicate-process checks, three-target ownership state and dashboard action UI. Keep this **off by default** until the migration is explicitly approved and tested.
2. **Disposable Windows end-to-end:** independently register and stop/start only CI-owned task instances, then run an isolated actual Velocity binary as a GSC-owned child, send `shutdown\n` over stdin, verify one instance, Java+Bedrock proxy compatibility, exit, restart, and check no orphan JVM. Do not infer production authorization from CI success.
3. **One approved maintenance/cutover:** snapshot/export only the three exact task definitions into an encrypted, access-restricted operator-local recovery archive; compare actual on-host launch specs without exporting private paths or keys; warn that any connected players will be gracefully disconnected, obtain explicit operator consent and a maintenance window; migrate one proxy at a time. Disable the original task **before** launching its GSC-owned replacement. Validate endpoints; restore original task definition/enablement from the exact snapshot on any failure. No surprise forced kills, no automated production restart without approval.
4. **Post-cutover:** leave the three old task definitions preserved and disabled (not deleted), while GSC owns process stdio for supervised start/stop/restart. Maintain rollback until an operator accepts full stability.

## Important hard limits

The current `StopPermit` is a typed **model input**, not a cryptographic capability. The hosted GSC API MUST authenticate a real privileged operator, obtain explicit confirmation that any connected players will be disconnected by Velocity's built-in console `shutdown`, and verify the old Scheduler tasks have been safely migrated. Caller-supplied JSON booleans alone are NOT verification. Never wire the status endpoint to a start/stop/restart route simply because a unit test passes; perform a supervised rollback-capable cutover first.

**User action now: none.** No existing task, server or release is modified by this Draft work.


## Additional integrated host/API implementation (locked by default)

The source-only Canary GSC host now has **real wired but default-locked** routes:

- `GET /api/v1/velocity/tasks`: three fixed Day10 Windows Scheduler states, sanitized and read-only.
- `GET /api/v1/velocity/managed/status`: whether a direct-ownership cutover has been opted in and whether a GSC-owned child is running; capability buttons denied by default.
- `POST /api/v1/velocity/managed/action`: `start`, `stop`, `restart` for GSC-owned children only. Until an operator deliberately sets `GSC_VELOCITY_MANAGED_OPERATOR_OPT_IN=DIRECT_OWNERSHIP_APPROVED` on the **GSC host service** and performs a separate approved migration, the route returns **HTTP 423 Locked**. It additionally requires the authenticated **host API token**, **loopback** caller, a typed disconnect approval, a disabled exact Day10 task, and (on start) free Java TCP/Bedrock UDP listener ports plus an exact per-target *locally protected* launcher manifest and Velocity jar SHA verification. A request cannot include executable path, arbitrary task name, external port or commands. All start/stop/restart buttons in the GSC dashboard are disabled unless the Canary and cutover prerequisites are met.

The manifest is read only from `%ProgramData%\GeumyiServerCenter\VelocityManaged\<target>.json` and has schema 1 with `target`, `java_executable`, `working_directory`, `args`, `expected_jar_sha256`; the expected Velocity jar SHA is currently pinned to the operator-reported 4.2.0 build 30 hash. The working directory must match the vetted `%ProgramData%\GeumyiServerCenter\Network\FourServer\<target>` and `java_executable` must name an actual `java.exe`. Unknown fields, wrong jar, relative paths and unsupported Java agent options are rejected. The one-time manifest export/ACL audit from existing Task Scheduler task definitions is **not implemented yet**. Do not hand-author or copy a manifest with a guessed JVM command.

**WARNING: do not manually activate the environment opt-in or disable old tasks.** Source-only route tests prove default locking, invalid target rejection and missing/bad manifests. The existing production build and server have NOT been updated. The remaining gap before rollout is an actual preflight/cutover/rollback operator kit, correct config/ACL provenance, GSC host restart/orphan recovery, real Java+Bedrock login E2E and maintenance approval. Official Velocity 4.2.0 CI-only JVM start→graceful-console-stop→restart→stop already passed, but does not authorize migrating running proxies.

