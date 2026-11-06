Geumyi Server Center 5.0.0-beta.1 — SINGLE BETA (2026-10-25)

Host, Client and Setup 5.0.0-beta.1 built from GSC 4.5.1 Stable source.
GSCM remains separately versioned 1.5.1+151; compatible v4 API retained.

Preserved functions: monitoring, dashboard, console, authenticated remote
controls, update center, verified staging, backups and restore preflight,
Golden protection, companion agent, RCON/metrics, local and remote roles,
GSC Host/Client self-update separation and Windows service operation.

New: unified Host/Client/Setup 5.0.0-beta.1 identity, release manifest
catalog coherence, authenticated read-only /api/v5/release capabilities.

IMPORTANT: original Windows Scheduled Tasks continue to own all Velocity
proxies. The abandoned direct Velocity management Canary experiment is NOT
part of this beta. NO auto-Stable promotion; Stable 5.0.0 only by operator.
This BETA is NOT verified as installed on a production server and does
not prove Java/Bedrock/iOS/Android E2E. It has no newly signed deployment
manifest. Do NOT replace live services without a tested backup/rollback.
Never upload server.json, client.json or token/journal/key files to GitHub.
