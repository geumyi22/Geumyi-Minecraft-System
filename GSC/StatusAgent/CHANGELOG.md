# GeumyiStatusAgent 0.5.4

- Discord status now includes newly discovered GDS servers even before a manual Agent config edit.
- Slash-command server choices are generated from the managed server catalog instead of being hardcoded to wild/playground.
- Server display names and GSC ID mappings are resolved from `agent.properties`, allowing newly added GSC profiles to work after automatic reconciliation.
- Keeps the 0.5.2 health semantics, GDS fallback, GSC Control API and graceful shutdown behavior.

# 0.5.2
- Separates management-only GSC warnings from actual server degradation.
- A legacy GSC `DEGRADED` caused only by RCON does not override fresh HEALTHY heartbeat/GDS/GST state.
- Pulls reconciled online/max-player values from the GSC server view when available.
- Discord status reports `RCON 제한` separately instead of calling the server performance/integration degraded.
- Retains local GDS API fallback, ingest diagnostics, graceful shutdown, RBAC and GSC-only management routing.

# 0.5.0
- Added GSC Control API-backed Discord management commands.
- Added RBAC, destructive-action confirmation, and delegated audit attribution.
- Split Discord Gateway scheduling from REST/GSC I/O and added virtual-thread workers.
- Added loopback-only graceful shutdown endpoint.
