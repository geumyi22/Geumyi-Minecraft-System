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
