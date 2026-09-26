## 1.1.1 - Spigot/Paper 26.3 compatibility hotfix
- Removed hard linkage to Paper-only TPS/MSPT and world count methods.
- Added reflective Paper metrics with scheduler/CPU-time fallback on Spigot.
- Bridge `/ingest` request creation and send now begin on the dedicated bridge executor.
- Direct Discord webhook request creation/send also runs off the Minecraft main thread.

# Changelog

## 1.1.0
- GeumyiServerTools 1.1 Diagnostics v2 (`runtime/health-v2.json`) 비동기 연동.
- GST structured lag incident stream (`runtime/lag-events.jsonl`) start/recovered relay 추가.
- `/api/v4/gst` 추가, `/api/v4/status`와 `/api/v4/diagnostics`에 GST 진단 포함.
- outbound heartbeat/event에 `gst_version`, `gst_grade`, `gst_lag_active`, `gst_incident_count`, `gst_health_time` 추가.
- GST가 DEGRADED/CRITICAL이면 GDS mode도 DEGRADED로 반영(maintenance/restart 우선순위 유지).
- safe action에 `whitelist_add`, `whitelist_remove` 추가. 플레이어명은 Java Edition 형식 `[A-Za-z0-9_]{1,16}`으로 검증해 명령 주입 차단.
- action audit에 `X-GSC-Actor`, `X-GSC-Actor-Id`, `X-GSC-Source` 메타데이터 기록 지원.
- capability에 `gst_diagnostics_v2`, `structured_lag_events`, `actor_audit`, `whitelist_manage` 추가.
- 기존 protocol v4, Agent ingest, 1.0.x API/설정 하위 호환 유지.

## 1.0.1
- 정상 종료 시 shutdown 뒤 heartbeat를 보내지 않도록 수정해 Agent의 비정상 오프라인 오판을 방지.
- shutdown payload에 planned=true를 명시하고 종료 시 bridge 전송을 짧게 flush.

## 1.0.0
- GSC v4 bridge protocol 4 추가 및 legacy Agent 호환.
