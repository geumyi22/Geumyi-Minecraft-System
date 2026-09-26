# GeumyiStatusAgent 0.5.4

Discord/GSC operations Agent for Geumyi Server Center.

## 0.5.4 changes
- Newly added GSC server profiles are supported without hardcoding wild/playground.
- `servers=` plus `server.<id>.*` and `gsc.server_id.<id>` are used to build the Discord status board and slash-command choices.
- GSC 4.2.2 automatically reconciles those catalog entries after server profile add/update/delete.
- Keeps the 0.5.2 health model: RCON-only warnings remain management limitations rather than false health degradation.
- Keeps local GDS API fallback probing, ingest diagnostics, graceful loopback shutdown, RBAC and GSC-only management routing.

## Runtime
Requires Java 21+.

## Security
Keep Agent and GSC on loopback/LAN/Tailscale. Do not expose ports 8877/8787 directly to the public Internet.
Bot token and shared secrets stay only in local `agent.properties`.
