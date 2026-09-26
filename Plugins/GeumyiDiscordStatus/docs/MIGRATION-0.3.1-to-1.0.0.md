# 0.3.1 → 1.0.0 migration

## 보존되는 항목

- plugin name / data folder: `GeumyiDiscordStatus`
- `/gds` command
- `server.id`, `server.name`
- legacy `agent.*`
- `/health`, `/api/status`
- performance thresholds
- GST alerts.log relay
- DiscordSRV join/quit suppression
- direct Discord webhook fallback
- events/metrics logs
- restart command-at-zero default OFF

## 새 항목

- `bridge.*`
- `/api/v4/*`
- safe action endpoint
- player/world/plugin/datapack snapshots
- event sequence/timeline
- bridge transport diagnostics
- HMAC outbound headers
- action audit log
- instance/boot IDs

## config migration behavior

Paper/Bukkit config defaults merge 방식으로 누락된 새 키를 추가합니다. 기존 값은 유지됩니다.
`bridge.url`이 비어 있으면 legacy Agent mode로 동작하여 `agent.enabled`, `agent.url`, `agent.heartbeat-seconds`, `agent.connect-timeout-ms`, `agent.request-timeout-ms`를 그대로 사용합니다. `bridge.secret`이 비어 있으면 `agent.secret`을 사용합니다.
