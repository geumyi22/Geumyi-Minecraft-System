# Geumyi Minecraft Bridge Protocol v4 — GDS 1.1 extension

GDS 1.1.0은 protocol version을 4로 유지하며 additive 필드만 추가합니다. 기존 Agent/GSC가 모르는 필드는 무시할 수 있습니다.

## Outbound 추가 필드
GST 1.1 Diagnostics v2가 사용 가능할 때 heartbeat/event payload에 다음이 추가됩니다.
- `gst_version`
- `gst_grade`
- `gst_lag_active`
- `gst_incident_count`
- `gst_health_time`

기존 `X-GDS-Secret`, `X-Geumyi-Protocol`, HMAC 헤더는 유지됩니다.

## GET /api/v4/gst
GST Diagnostics v2 cache를 반환합니다. 파일 읽기는 Minecraft main thread에서 수행하지 않습니다.
필드: available, version, time, age_seconds, stale, grade, lag_active, incident_count, performance, counts, last_incident.

## POST /api/v4/action
기존 safe action에 `whitelist_add`, `whitelist_remove`가 추가됩니다.
GSC는 다음 audit metadata를 전달할 수 있습니다.
- `X-GSC-Actor`
- `X-GSC-Actor-Id`
- `X-GSC-Source`
- `X-GSC-Request-Id`

임의 console command 실행은 지원하지 않습니다.
