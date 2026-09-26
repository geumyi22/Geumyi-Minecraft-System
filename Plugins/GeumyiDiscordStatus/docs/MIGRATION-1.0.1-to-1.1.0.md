# Migration: GeumyiDiscordStatus 1.0.1 -> 1.1.0

1. Stop the Paper server cleanly.
2. Replace the old GDS JAR with `GeumyiDiscordStatus-1.1.0-Paper26.3.jar`.
3. Keep the existing `plugins/GeumyiDiscordStatus/config.yml`; missing 1.1 defaults are copied automatically.
4. With GSC 4.1.2, use Companion Sync only while the server is stopped. It seeds GDS 1.1.0 and GST 1.1.0.
5. Start Paper and verify `/gds health`, `/gds status`, and `GET /api/v4/gst` on loopback.

New optional config keys:
- `integration.gst.health-max-age-seconds`
- `integration.gst.relay-lag-events`
- safe actions `whitelist_add`, `whitelist_remove`

Protocol remains v4; Agent/GSC consumers that ignore unknown additive fields remain compatible.
