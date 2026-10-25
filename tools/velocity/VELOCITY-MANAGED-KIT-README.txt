2026-10-25 LIVE HOST FEATURE ENABLED — VERIFIED BY OPERATOR
  Local GSC 4.5.2-canary Host response:
    canary_enabled=true, read_only=true, 3 tasks, 5.2 seconds
  The previous Apply script timed out after 2 seconds on GET. THIS IS NOT
  permission to rerun Apply or Restore. Existing proxies still 0/3 migrated.

2026-10-25 CRITICAL WILD TOKEN GATE AND VERIFY-ONLY
  OLD KIT BUG: read-only localhost managed/status GET can succeed even if
  X-GSC-Token is WRONG because Host may allow loopback without auth.
  Yet POST managed/action requires the real Host API token. Previously the
  original Wild task could be stopped before POST rejects that token.
  DO NOT USE THE OLD ATTENDED CUTOVER KIT.
  Updated kit includes GSC452_Host_Action_Token_Verifier.ps1.
  The operator tool now verifies the token AGAINST THE RUNNING Canary Host's
  actual --config token using Windows machine DPAPI entirely on the local PC,
  with no printed keys, task changes, or control/action POST probe.
  Any unverified token refuses maintenance before player disconnection.
  Run_GSC452_Wild_Attended_Cutover_VERIFY_ONLY.cmd performs the identical
  pre-mutation original-receipt/JAR/Host/action-token/non-target task checks
  and exits without ever disabling/stopping a proxy.
  This is the new FIRST operator step. Only a proven PASS can precede an
  attended approved maintenance; confirmation still explicitly warns it is
  not a Velocity console-graceful disconnect.
  The updated Host GET client timeout is 20s to accommodate the 5s
  internal Windows Scheduler poll.

GEUMYI GSC 4.5.2 CANARY — VELOCITY CUTOVER KIT (2026-10-23)
================================================================
DRAFT PR #57 ONLY. LIVE MIGRATION 0/3. NOT A STABLE RELEASE.

OPERATOR AUTHORIZATION AND CURRENT FACTS
  The operator explicitly approved maintenance, including restarting or
  stopping Velocity and Windows task/configuration changes. The approval
  is NOT evidence of exact task-to-JVM identity, deployable GSC Host
  capabilities, or a recoverable shutdown. This GitHub session cannot
  execute commands on the owner's Windows server PC.
  Wild Java client login succeeded. Playground client login is not
  independently established in the latest session. Other Paper server
  is intentionally OFF; its Velocity Scheduled Task may still run.
  On-host reports identify three parent/child Velocity-JAR JVM pairs,
  with UDP19132/33/34 owners in child JVMs; scheduler task instance
  PID ownership is still not proven. Existing wild client access must
  not be damaged solely to fix the prior TCP LISTEN=0 observation.

WHAT IS VERIFIED IN ISOLATED WINDOWS CI
  Source: Velocity_Managed_Cutover.ps1.
  It now uses only Get-NetTCPConnection and Get-NetUDPEndpoint to inspect
  TCP/UDP port occupancy; it never probes by transiently opening a port.
  ANY matching local TCP endpoint (LISTEN or ESTABLISHED), UDP endpoint,
  or query failure blocks Cutover. Isolated Windows CI verified:
   * empty-port Preflight;
   * TCP 25565 occupied -> Cutover readiness DENIED;
   * UDP 19132 occupied -> Cutover readiness DENIED;
   * private XML Snapshot, Ready-task disable, receipt commit,
     Rollback to Ready, and fixture cleanup.
  This does not prove it is safe to stop a RUNNING production task.

PROTECTED SNAPSHOT — DO NOT REPEAT
  The operator previously reported original 3-task Snapshot PASS,
  including protected ProgramData Recovery records and fixed manifests.
  DO NOT rerun the fleet snapshot or overwrite records. Tickets and
  private manifest/task XML are to stay local. Before production cutover,
  validate those EXACT existing protected receipts, binary artifacts,
  task XML, launch spec, GSC host capability, and rollback readiness.
  Never guess/change the protected maintenance ticket.

EXISTING RECOVERY EVIDENCE — SAFE READ ONLY (NEW)
  Run_GSC452_Wild_Existing_Evidence_READ_ONLY.cmd
  This ONE-target wild read-only check loads the EXISTING protected
  original task XML, verifies the private receipt/hash and exact Java
  launcher manifest, compares current task definition (ignoring only
  Scheduler's intended Enabled bit), and checks the real velocity.jar
  SHA-256 against the pinned official build. It NEVER writes the
  private files, creates a new snapshot, stops/starts Java, changes a
  Scheduled Task, or enables direct ownership.
  Execute on the SERVER PC, preferably in an elevated CMD context if
  protected Recovery ACLs deny ordinary access. The output is sanitized:
  no private ticket/command line/XML/paths/PIDs/tokens are printed.
  Any missing or changed snapshot/manifest blocks the check. A valid
  snapshot is NOT proof legacy parent/child JVMs exited; live cutover
  remains prohibited until process ownership and shutdown are proven.
  The disposable Windows CI fixture deliberately has no Velocity JAR,
  so its pin-check field is false while archive integrity still passes.

RUNNING TASK MAINTENANCE — NEW DRAFT CANDIDATE (WILD ONLY)
  The production operator reported the existing Wild snapshot, original
  task XML, launcher manifest, and actual Velocity JAR hash all MATCH.
  Current Wild legacy Scheduler state is Running; TCP/UDP ports occupied;
  owner marker absent; live cutover remains 0/3 as of operator evidence.

  The Draft contains a guarded script -Mode DrainAndCutover.
  It REQUIRES the same original, locally protected snapshot and ticket.
  It checks the real Geyser UDP owner is a Java velocity.jar JVM,
  captures its PID plus creation time (and verified JVM parent, if any),
  disables future Scheduled Task starts, requests Stop-ScheduledTask on
  ONE exact task, and waits for those OLD JVM identities to exit and BOTH
  front ports to be released. Only then may it mark the cutover receipt.
  IT NEVER FORCE-KILLS by PID and NEVER starts Paper, Velocity or worlds.
  Windows Scheduler Stop is NOT an external JVM's console-graceful
  shutdown. Existing players can be immediately disconnected.
  If a child JVM/port survives or postcheck fails, the original task
  stays Disabled; DO NOT launch another JVM or blindly enable it.
  A valid receipt alone is NOT proof of a full end-to-end production
  migration. Only official protected source + validated process identity.

  The optional ATTENDED wrapper is:
    Run_GSC452_Wild_Attended_Cutover_ADMIN.cmd
  It requires (a) local Admin, (b) CURRENT VerifyExisting PASS incl jar,
  (c) GSC Host authenticated local status API at 127.0.0.1:8787
  reporting Canary direct ownership enabled, (d) manually entered HOST
  API token IN THE SERVER CONSOLE ONLY, and (e) typed explicit PLAYER
  DISCONNECT consent. It does not transmit private ticket/path outside
  the host; it calls the core script IN-PROCESS and only requests GSC
  start AFTER the original task is committed Disabled and ports empty.
  START ACK is not full Java/Bedrock gameplay/route health evidence.
  If the Host Canary flag is not enabled, the wrapper MUST deny without
  any task or JVM change; do NOT work around the gate.

  Original task manual recovery wrapper:
    Run_GSC452_Wild_Attended_Restore_ADMIN.cmd
  This requires Admin, local original XML/hash and receipt, NO GSC
  active/orphaned ownership, empty TCP/UDP ports, validated local HOST
  API status, and distinct typed RESTORE consent. It then uses the
  existing Rollback mode to restore the exact original task, followed
  by an explicit Start-ScheduledTask request. Never perform recovery if
  GSC might still own an unbound or orphan Java process.
  BACKUP/ROLLBACK cannot be inferred merely from a stale PID scan.
  This tool is not production-approved until dedicated Windows CI,
  Host Canary readiness, rollback staging and operator observation
  have been validated. Never run all three proxies simultaneously.

  Isolated CI additionally validates a unique no-trigger dummy Running
  task can have Settings.Enabled=false while its task.State is still
  Running, then a subsequent Stop-ScheduledTask must be separately
  verified. Neither this CI proof nor the existing Velocity shutdown
  CI demonstrates a live parent-child JVM was actually terminated.
  Playground and Other are intentionally NOT in the attended kit.
  Other PAPER game server remains intentionally OFF.

2026-10-25 HOST MANAGED CONTROL OPT-IN — CURRENT USER NO-GO
  Operator executed Wild attended cutover and obtained:
    WILD_PROTECTED_EVIDENCE_AND_CURRENT_JAR=PASS
    WILD_MAINTENANCE_NO_GO: GSC_HOST_CANARY_DIRECT_OWNERSHIP_NOT_ACTIVE
  This occurred BEFORE the script's player-disconnect approval and BEFORE
  any Scheduler stop, JVM shutdown or migration. Host 4.5.2 Canary was
  previously activated, but Velocity direct ownership is intentionally
  DEFAULT-LOCKED. DO NOT repeat protected snapshots or disable tasks.

  NEW separate Host-only candidate, not automatically deployed:
    GSC452_Host_Managed_OptIn.ps1
    Run_GSC452_Host_Managed_OptIn_PLAN_READ_ONLY.cmd
    Run_GSC452_Host_Managed_OptIn_APPLY_ADMIN.cmd
    Run_GSC452_Host_Managed_OptIn_RESTORE_ADMIN.cmd

  FIRST OPERATOR ACTION is Plan ONLY (run as administrator). Plan requires
  original 3 Scheduler tasks Running, private receipts uncommitted, no
  GSC-owned markers, pinned Canary Host executable/actual service process,
  currently responsive localhost Canary managed/status with flag FALSE,
  and auto-start Paper backends already online. Plan NEVER changes registry,
  SCM, task definitions, Java processes, worlds, original snapshots or tokens.
  If Plan fails, DO NOT try Apply to bypass it.

  Apply is a LATER, explicitly approved, ATTENDED GSC Host service restart:
  adds an opt-in to only THIS service's REG_MULTI_SZ Environment, stores
  any original Environment as PRIVATE JSON in the already protected Recovery
  directory (never upload it; it might contain unrelated secrets), and
  requires operator confirmation. No global machine Environment mutation,
  no Velocity/Paper stop, no task edit, no GSC-owned Java launch.
  It independently validates localhost Canary managed/status flag TRUE
  after restart. Service restart may indirectly interact with auto-start
  Paper backend logic; therefore currently-offline configured auto-start
  backends are NO-GO. Do not use during active changes or live migration.
  If partially interrupted, private journal is preserved for manual
  restore. Do not repeat Apply blindly.

  Restore is only allowed BEFORE ANY proxy was cut over, while all three
  original tasks are Running, and no GSC-owned/orphan process marker exists.
  It returns the exact service-specific Environment setting and restarts
  only GSC Host, then checks Canary flag FALSE; no automatic task restart.
  Never revert the flag after a GSC-owned proxy is running.

  Once Host-only opt-in is separately verified, the Wild attended cutover
  still requires existing original receipt, operator/API token and distinct
  player-disconnect consent. Live migration is STILL 0/3. Java and Bedrock
  real-client tests and orphan/restart recovery remain pending.
  Previously exposed Host API token should be rotated in a separate
  controlled client/GSCM pairing session, not mixed into this operation.

CURRENT PRODUCTION NO-GO GATES
  - Original Day10 tasks were Running and RestartOnFailure=999.
  - Old Velocity Java consoles' stdin control is not available to GSC.
  - This kit has NO stop/kill action for a Running legacy task.
  - Direct management requires task Disabled, exact approved receipt,
    pinned velocity.jar, protected manifest, freed ports, Host opt-in,
    authentication, and an owner-generation marker.
  - Stop-ScheduledTask IMMEDIATELY stops task instances; it is not the
    Velocity console-only graceful shutdown command. It might leave
    child JVMs alive, and scheduling retries must first be inhibited.
  - Disabling a task does not prove its JVM exited. NEVER disable three
    production tasks at once or enable a legacy task while an old child
    or GSC-owned generation might still exist.
  - Rollback reenables the exact task but does NOT automatically start
    the original JVM. A dedicated recovery start/join verification is
    needed. Failure can produce downtime.

WHAT THIS PACKAGE CAN DO NOW
  Run_Velocity_Managed_PRECHECK_READ_ONLY.cmd  (READ ONLY).
  Velocity_Managed_Cutover.ps1 -Mode Snapshot   (privileged, approved).
  Velocity_Managed_Cutover.ps1 -Mode Cutover    (Ready only, never Running).
  Velocity_Managed_Cutover.ps1 -Mode Rollback   (Disabled only, ports free).
  DO NOT use the privileged modes merely because the user gave broad
  approval. Need an independently verified and tested running-task
  shutdown/cleanup and host-opt-in/recovery procedure before live use.
  PR #57 is Draft and existing main, Stable release and worlds are intact.

SECURITY
  Do not share task XML, local ticket, raw JVM command lines, absolute
  private paths, PIDs, secrets, configs, launcher manifests, or
  Geyser/Floodgate keys. Only sanitized status output is shareable.
  https://github.com/geumyi22/Geumyi-Minecraft-System/pull/57
