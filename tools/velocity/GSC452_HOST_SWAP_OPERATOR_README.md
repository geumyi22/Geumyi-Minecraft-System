# GSC 4.5.2 Canary Host swap — operator kit

**Draft PR #57.** This is an explicitly operator-confirmed GSC Host **service-only** switch, not a Minecraft server or Velocity migration. It changes the registered executable target to an already staged SHA-verified 4.5.2 binary and retains the installed original binary untouched.

## Preconditions

- Operator has already completed `SNAPSHOT_ONLY` for wild/playground/other, `CANARY_STAGED_NO_INSTALL` and `HOST_SWAP_ROLLBACK_PREFLIGHT_PASS_NO_INSTALL`. Do not rerun their creation commands.
- The existing running Windows service is GSC v4.5.1, LocalSystem. The staged Canary/original Host and private XML/receipts are accessible only to SYSTEM/Administrators.
- No owned JVM generation marker; three Velocity legacy tasks **Running**. If not, the swap is blocked.
- All configured GSC `auto_start` Minecraft server TCP endpoints must currently respond to prevent the GSC startup supervisor from unexpectedly launching offline backends. This is a partial safety mitigation, **not proof** of no indirect application side effects.
- The swap script rejects an already-existing private journal; never delete it merely to retry. A journal contains private service paths: **never upload or share it**.

## Usage

1. Run `Run_GSC452_Host_Swap_WITH_AUTO_ROLLBACK_ADMIN.cmd` as Administrator; it first performs a live **Plan** check with zero changes.
2. To allow the short GSC Host service interruption, type `APPLY`. The script switches only the service `binPath`, starts it, checks local `/api/health` returns version `4.5.2-canary`, verifies task states and no orphan markers.
3. If activation fails, it *attempts* restoring the original v4.5.1 service path and health. It prints `HOST_CANARY_AUTO_ROLLBACK_VERIFIED` only if the original service actually reports healthy.
4. **Never** assume rollback worked after `HOST_CANARY_MANUAL_RECOVERY_REQUIRED` or `HOST_SWAP_BLOCKED_OR_UNCONFIRMED`. Do not start a second Host or restart Paper/Velocity manually; share only sanitized status.
5. Later, `Run_GSC452_Host_Rollback_ONLY_ADMIN.cmd` can revert a healthy Canary with the private journal, provided the three legacy tasks are still Running and no GSC-managed owner marker exists. It deliberately preserves the journal and staging originals.

## Scope/limitations

- **Changed:** Windows SCM `Geumyi Server Center Host` launch target, GSC Host service stop/start, private Host swap journal.
- **Not directly changed:** existing original GSC Host EXE, `server.json`, Velocity Scheduled Tasks, Paper worlds, Geyser/Floodgate keys, plugins, Java processes, firewall/ACL rules.
- **Indirect Host startup behavior exists** (GSC starts its own supervisor, agent watchdog and other routines). Even after green isolated CI, live validation and operator attention are necessary. Check GSC dashboard and game clients afterward.
- This phase does **not** enable `GSC_VELOCITY_MANAGED_OPERATOR_OPT_IN`. Managed Velocity control remains default off. Do not run `Velocity_Managed_Cutover.ps1` yet.

Verification: PowerShell Windows parser, default-locked Plan, synthetic classification, nonmutation AST checks and isolated Canary binary tests in System CI. Synthetic tests are **not an end-to-end rehearsal of a production SCM service replacement**.
