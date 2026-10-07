# Geumyi Minecraft System — 작업 로드맵

기준일: 2026-10-07

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
| 11 | Operations UX & Fleet Management — GSC 4.3.8 / GSCM 1.1.5+117 | ✅ 완료 |
| 12 | Final Production Hardening & Closure | 🔄 진행 중 — repository/CI prep verified; live closure gates pending |

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

최종 검증 기준:
- **GSC 4.3.8 (live)**
- **GSCM 1.1.5+117 (live verified; final two requested device checks user-confirmed PASS)**

진행 상태:
- **11.0~11.6 완료**
- **11.6 Full Fleet UX LIVE PASS**
- **11.7 Protection & Recovery 2.0 LIVE PASS**
- **Day 11 Final READ-ONLY integrated E2E PASS**
- **real Java + Bedrock client smoke USER PASS**
- **마지막 GSCM 1.1.5+117 관련 2개 device check USER PASS**
- **Day 11 COMPLETE** — 세부 근거: `DAY11-FINAL-REPORT.md`

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

Day 11 11.6 live evidence:
- signed Canary rollout Playground -> Wild -> Other -> Lobby
- offline Other health gate fail-closed 확인
- Other 백업/SHA 검증 후 Technology 0.1.4 실제 적용 + post-start health PASS
- rollout 완료 후 전 서버 `managed + inherit + no pin`, global beta 복귀
- GSC 4.3.7에서 원격 관리 PC의 **로컬 Client 업데이트**와 서버 PC의 **Host 업데이트** UI/실행 경로를 분리했고, 두 PC 4.3.7 설치 후 실제 원격 화면에서 분리 상태/버전 감지 LIVE PASS
- 11.7은 GSC 4.3.8 / GSCM build117 후보에서 provenance, 보호/Trash, 영구삭제 서버 확인 토큰, retention, restore preflight/checkpoint/offline-health/rollback 경로를 구현/검증 중
- 원격 관리 PC의 **인앱 Client-only 4.3.7 → 4.3.8 self-update** 사용자 실기기 E2E PASS
- 서버 PC GSC Host도 사용자 확인 기준 **4.3.7 → 4.3.8 self-update PASS**
- 11.7 Phase 7 READ-ONLY 실서버 검증 **PASS**: GSC 4.3.8, 4개 서버 inventory/retention 조회, Other 기존 full backup restore-preflight PASS, 영구삭제 확인 게이트 400 PASS, mutation=false
- 11.7 safe disposable config-backup lifecycle E2E도 PASS: protect/409 deny, Trash/restore, permanent-delete missing-confirm 400, retention dry-run, restore preflight, final recoverable Trash
- **Phase 11.7 완료.** 세부 근거: `DAY11-PHASE7-REPORT.md`

Day 11 안정화 버그:
- RCON `관리 제한` 오탐 방지
- 정상 종료 후 `자동 복구 중` 오표시 수정
- 콘솔 `stop`을 의도적 종료로 인식
- 의도적 종료 -> OFFLINE / 실제 crash -> RECOVERING -> 자동 재시작

## Day 12 — Final Production Hardening & Closure

Day 12는 신규 기능을 계속 늘리는 단계가 아니라 **장기 무인/저관리 운영이 가능한 최종 제품 상태**를 만드는 마지막 milestone입니다.

- Golden Baseline / final freeze
- ResourcePack/DataPack managed deployment
- StatusAgent 및 남은 자체 구성요소 update 경로 통합
- whole-system read-only health report
- backup retention / disk guard / log lifecycle
- SBOM/provenance/dependency/secret/security scans
- trusted/reproducible build hardening
- shared artifact cache / offline known-good operation
- disaster-recovery drill + Recovery Kit
- GSC/GSCM final UX cleanup
- read-only Final Verification tool
- Java + Bedrock + GSCM final live E2E
- extended soak test
- Stable final release 후 Maintenance Mode 전환

세부 단계 및 완료 Gate: [DAY12-PLAN.md](DAY12-PLAN.md)

## 운영 원칙

- GitHub `main` 자체가 배포 대상이 아니라 검증된 artifact/manifest가 배포 기준
- CI/검증을 통과하지 않은 artifact는 Stable 진입 금지
- 서버 시작 전 staging + checksum/signature + backup + atomic replacement
- 인터넷/다운로드/검증 실패 시 기존 정상 버전으로 시작
- health 실패 시 rollback
- 자체/외부 업데이트 정책 분리
- Android/iOS 플랫폼 제약 분리
- 실제 E2E 없이 완료/정상 작동 선언 금지
