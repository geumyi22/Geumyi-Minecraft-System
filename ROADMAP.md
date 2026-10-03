# Geumyi Minecraft System — 작업 로드맵

기준일: 2026-10-04

> **일차 번호와 상태의 단일 기준은 [DAY-TIMELINE.md](DAY-TIMELINE.md)입니다.**
> Day 번호는 개발 날짜 수가 아니라 milestone 번호입니다. Day 4는 삭제된 일차가 아니라 **신규 구현 없이 실서버 E2E 검증/마감을 수행한 milestone**입니다.

| Day | 목표 | 상태 |
|---|---|---|
| 1 | Source Recovery / Baseline | ✅ 완료 |
| 2 | CI & Component Verification | ✅ 완료 |
| 3 | Component Recovery / Configuration | ✅ 완료 |
| 4 | Live E2E Verification & Closure — 신규 구현 없음 | ✅ 완료 |
| 5 | Operations Stability | ✅ 완료 |
| 6 | GSCM Android+iOS Device Verification | ✅ 완료 |
| 7 | Build Foundation | ✅ 완료 |
| 8 | Secure Release & Update Foundation | ✅ 완료 |
| 9 | Transaction / Backup / Rollback | ✅ 완료 |
| 10 | Full E2E + Lobby / Proxy Network | ✅ 완료 |
| 11 | Operations UX & Fleet Management — GSC 4.3 / GSCM 1.1.5 | ⏳ 예정 |
| 12 | Extended Automation & Production Hardening | ⏳ 예정 |

## Day 1~3 — 복구와 기반 정리

- Day 1: GitHub 소스 복구·정리, 버전 기준 통일.
- Day 2: GSC/GDS/ResourcePack 등 초기 CI/구성요소 검증 기반 구축.
- Day 3: GST 1.1.1 HOTFIX, StatusAgent, Technology, Chemistry 복구와 Wild/Playground 설정 근거 정리.

## Day 4 — Live E2E Verification & Closure

Day 4는 **신규 기능 구현 일차가 아닙니다.** 당시 “더 할 것이 없다”는 의미는 Day 4가 존재하지 않는다는 뜻이 아니라, 추가 구현 없이 기존 구성을 실제 서버에서 검증하고 마감한다는 뜻으로 정리합니다.

확인 범위:
- Wild/Playground Paper 26.3
- GSC 4.2.3
- GSCM 1.1.2
- StatusAgent 0.5.4
- GST 1.1.1 HOTFIX
- GDS 1.1.1
- 후속 비차단 항목 정리

세부 근거: [DAY4-E2E-REPORT.md](DAY4-E2E-REPORT.md)

## Day 5 — Operations Stability

사용자 실운영 기준으로 시작/정상 종료/재시작/강제 종료, 중복 명령/락, GSC·Agent 재연결, 네트워크 복구, Whole Shutdown, 고아 프로세스, Other 상태/알림을 확인했습니다.

세부 근거: [DAY5-STABILITY-REPORT.md](DAY5-STABILITY-REPORT.md)

## Day 6 — GSCM Device Verification

Android/iOS에서 페어링, 인증 지속, 앱/기기 재시작, HTTP snapshot, WebSocket realtime, 네트워크 끊김/복구, 서버 제어를 사용자 실기기로 검증했습니다.

## Day 7 — Build Foundation

GSC, StatusAgent, GST, GDS, Technology, Chemistry, ResourcePack, GSCM Android/iOS 자동 build/test/artifact 체계를 실제 GitHub Actions에서 통과시켰습니다.

세부 근거: [DAY7-CI-REPORT.md](DAY7-CI-REPORT.md)

## Day 8 — Secure Release & Update Foundation — 완료

완료 범위:
- Stable/Beta/Canary
- SHA-256 artifact verification
- Ed25519 signed deployment manifest
- persistent Android release-signing path
- GSC pre-start updater + fail-open
- GSC Update Center 1차
- Wild Technology 0.1.4 실제 pre-start update
- Playground isolation
- 서버 PC finalizer PASS

세부 근거: [DAY8-RELEASE-REPORT.md](DAY8-RELEASE-REPORT.md), [DAY8-RUNBOOK.md](DAY8-RUNBOOK.md)

## Day 9 — Transaction / Backup / Rollback — 완료

완료 범위:
- transaction backup/staging/commit
- atomic replacement
- transaction journal
- release-group failure recovery
- interrupted transaction recovery
- post-start health gate
- automatic rollback
- rejected-release hold
- GitHub/update lookup 장애 시 known-good fail-open
- failure-injection/self-test
- 서버 PC Final E2E PASS

Day 8과 Day 9의 E2E PASS는 “부분 완료” 표기가 아니라 **완료 근거**입니다.

## Day 10 — Full E2E + Lobby / Proxy Network

Java 실제 검증 완료:
- Velocity 3개 재부팅 후 자동 시작
- public Java TCP 25565/25566/25567
- public entry -> Lobby
- Lobby -> Wild / Playground / Other
- `/lobby`
- 서버별 마지막 위치 복원

Bedrock:
- UDP/Geyser/Floodgate 기반 구성 완료
- 2026-10-04 사용자 실기기 확인으로 Bedrock 접속/서버 이동/복귀 동작 정상 확인
- 사용자 확인 기준 real-client E2E PASS

따라서 **Day 10 완료**로 닫습니다. 이 결과는 사용자 실기기 확인이며 assistant-side 직접 실행으로 기록하지 않습니다.

세부 근거: [DAY10-PLAN.md](DAY10-PLAN.md), [DAY10-E2E-REPORT.md](DAY10-E2E-REPORT.md)

## Day 11 — Operations UX & Fleet Management

목표 버전:
- **GSC 4.3**
- **GSCM 1.1.5**

고정 범위:
- GSC/GSCM 시작 시 최신 검증 빌드 확인
- GSC 자체 업데이트 흐름
- Android update / iOS signing 제약에 맞는 GSCM update UX
- GSC Full Update Center + GSCM remote controls
- channel / pin / hold / dry-run
- next-start / next-restart / maintenance-window
- player-aware restart/update
- canary promotion
- update history/audit/notifications
- Geyser/Floodgate/ViaVersion/ViaBackwards 업데이트 정책
- Paper는 별도 호환성/승인 정책

Day 11 안정화 버그:
- RCON `관리 제한` 오탐 방지
- 정상 종료 후 `자동 복구 중` 오표시 수정
- 콘솔 `stop`을 의도적 종료로 인식
- 의도적 종료 -> OFFLINE / 실제 crash -> RECOVERING -> 자동 재시작

## Day 12 — Extended Automation & Production Hardening

- ResourcePack/DataPack managed deployment
- resource-pack SHA/UUID/property 자동화
- StatusAgent/확장 self-update
- SBOM/provenance/dependency/security scans
- reproducibility hardening
- shared artifact cache / offline operation
- disaster-recovery drill
- Day 10 Lobby/Proxy를 fleet/update 정책과 최종 통합 검증

## 운영 원칙

- GitHub `main` 자체가 배포 대상이 아니라 검증된 artifact/manifest가 배포 기준
- CI/검증을 통과하지 않은 artifact는 Stable 진입 금지
- 서버 시작 전 staging + checksum/signature + backup + atomic replacement
- 인터넷/다운로드/검증 실패 시 기존 정상 버전으로 시작
- health 실패 시 rollback
- 자체/외부 업데이트 정책 분리
- Android/iOS 플랫폼 제약 분리
- 실제 E2E 없이 완료/정상 작동 선언 금지
