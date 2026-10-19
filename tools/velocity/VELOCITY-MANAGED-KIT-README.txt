GEUMYI GSC v4.5.2 Canary — Velocity Managed Cutover Kit
========================================================

SAFE FIRST STEP
  Extract the ZIP into one folder on the Windows server PC.
  Double-click Run_Velocity_Managed_PRECHECK_READ_ONLY.cmd.
  It queries only three exact fixed Day10 Scheduled Tasks (wild,
  playground, other), their Windows task states, and TCP/UDP port
  availability. It makes NO task edits, restarts, ACL, DPAPI or key changes.

DO NOT RUN CUTOVER WHILE THE TASK IS RUNNING.
  This tool is not a process stopper. The currently running old
  Velocity JVM must be independently and safely stopped during an
  operator-approved maintenance window before a cutover is possible.
  A Running result necessarily blocks a Cutover.

PRIVILEGED MODES ARE NOT YET AUTHORIZED ON PRODUCTION
  Velocity_Managed_Cutover.ps1 supports Snapshot, Cutover, Rollback
  only with an operator's explicit -Approved switch and unique -Ticket.
  Snapshot makes a protected local backup and derives a launcher manifest
  from exact task XML; Cutover disables only the chosen Ready task after
  free-port and integrity proofs; Rollback only re-enables it after the
  GSC-owned JVM has stopped and no active-generation marker remains.
  Rollback does not automatically start Java. Never blindly delete an
  active/orphan marker or force-stop a task-owned JVM.

SECURITY
  Never upload task XML, private recovery archives, Java commands,
  username/SID lists, server paths, credentials, VPN keys or
  Geyser/Floodgate secrets. Share only sanitized READ ONLY outputs.
  The full source and operator runbook are in PR #57:
  https://github.com/geumyi22/Geumyi-Minecraft-System/pull/57

STATUS
  The functional cutover/rollback tools and GSC backend are Draft/Canary
  source, not an installed update, Stable release or live server change.
  Java+Bedrock actual player login and host-restart recovery must pass
  operator-attended verification before full production activation.
