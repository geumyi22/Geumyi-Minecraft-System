# GeumyiDiscordStatus 1.1.1

Recovered from ChatGPT Library GeumyiDiscordStatus-1.1.1-Source.zip. The source, compile-only API stubs, default configuration, tests and build script are included. See BUILD.md.

## GSC v4.1 Bridge

Paper 26.3 서버 안에서 상태/이벤트/플레이어/플러그인 정보를 구조화해 GSC와 GeumyiStatusAgent에 전달하는 Minecraft-side bridge입니다.
Discord Gateway Bot 자체는 이 플러그인의 역할이 아닙니다. Bot Token은 Paper 플러그인에 넣지 않습니다.

## 1.1 핵심
- GSC/Agent용 protocol v4와 1.0.x API 하위 호환 유지.
- 모든 외부 HTTP 및 GST 파일 읽기를 비동기 처리.
- GST 1.1 `health-v2.json` 및 `lag-events.jsonl` 연동.
- GSCM용 구조화 진단: `/api/v4/gst`.
- safe actions: broadcast, save, maintenance, restart schedule/cancel, whitelist on/off/add/remove, kick.
- arbitrary console command API 없음.
- action idempotency + actor/source audit metadata.

## API
기본 bind는 `127.0.0.1`, 야생 기본 포트는 8766이며 놀이터는 8765로 분리합니다.
- GET `/health`
- GET `/api/status`
- GET `/api/v4/status`
- GET `/api/v4/capabilities`
- GET `/api/v4/players`
- GET `/api/v4/worlds`
- GET `/api/v4/plugins`
- GET `/api/v4/datapacks`
- GET `/api/v4/events?since=N`
- GET `/api/v4/diagnostics`
- GET `/api/v4/gst`
- POST `/api/v4/action`

## 보안
- 기본 loopback bind 유지 권장.
- loopback 밖으로 bind하려면 `api.token` 필수.
- safe action은 기본적으로 token 필수이며 arbitrary console command는 제공하지 않음.
- GSC 요청 시 `X-GSC-Request-Id`로 중복 실행 방지.
- `X-GSC-Actor`, `X-GSC-Actor-Id`, `X-GSC-Source`를 감사로그에 남길 수 있음.

## 서버별 설치
같은 JAR을 야생/놀이터에 사용합니다. `server.id`, `server.name`, `api.port`만 서버별로 다르게 설정합니다.
GeumyiTechnology/GeumyiChemistry 존재 여부와 무관하게 동작하며, 두 플러그인은 현재 야생 전용입니다.
