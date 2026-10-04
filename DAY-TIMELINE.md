# Geumyi Minecraft System — Canonical Day Timeline

기준일: 2026-10-04

이 문서는 프로젝트의 **일차 번호와 완료 상태를 결정하는 단일 기준(source of truth)** 입니다.
기존 `DAY*-*.md`, CI run, release, E2E 보고서의 역사적 번호는 이 문서의 번호와 동일하게 유지합니다.

## 번호 규칙

- Day 번호는 "코드를 새로 작성한 날짜 수"가 아니라 **프로젝트 milestone 번호**입니다.
- 따라서 신규 구현이 없는 검증/마감 전용 milestone도 정상적인 Day로 셉니다.
- 이미 생성된 report, workflow, artifact, release의 Day 번호는 재번호화하지 않습니다.
- 과거 대화에서 나온 "Day 4에 정확히 할 것이 없다"는 표현은 **Day 4가 존재하지 않는다는 뜻이 아니라, 추가 구현 없이 실서버 검증/마감만 남았다는 뜻**으로 정리합니다.
- 완료는 실제 사용자 실행/E2E 또는 명시된 CI/검증 근거가 있는 경우에만 표시합니다.

## Canonical timeline

| Day | Canonical milestone | 상태 | 핵심 근거/경계 |
|---|---|---|---|
| 1 | Source Recovery / Baseline | ✅ 완료 | GitHub 소스 복구·정리, 버전 기준 통일 |
| 2 | CI & Component Verification | ✅ 완료 | GSC/GDS/ResourcePack 등 초기 CI/검증 기반 |
| 3 | Component Recovery / Configuration | ✅ 완료 | GST HOTFIX, StatusAgent, Technology, Chemistry 및 Wild/Playground 설정 근거 복구 |
| 4 | Live E2E Verification & Closure | ✅ 완료 | **신규 구현 없음.** Wild/Playground 실서버와 GSC/GSCM/GST/GDS/Agent 경로 검증·후속항목 마감. See `DAY4-E2E-REPORT.md` |
| 5 | Operations Stability | ✅ 완료 | 시작/종료/재시작/강제종료, 락, 재연결, Whole Shutdown, 고아 프로세스 등 사용자 운영 검증. See `DAY5-STABILITY-REPORT.md` |
| 6 | GSCM Device Verification | ✅ 완료 | Android+iOS 페어링/인증/WS/HTTP/제어/재접속 실기기 검증 |
| 7 | Build Foundation | ✅ 완료 | 전체 컴포넌트 자동 build/test/artifact CI. See `DAY7-CI-REPORT.md` |
| 8 | Secure Release & Update Foundation | ✅ 완료 | signed manifest, SHA-256, Stable/Beta/Canary, pre-start updater, Wild Technology 0.1.4 실제 update + Playground isolation E2E |
| 9 | Transaction / Backup / Rollback | ✅ 완료 | transaction journal, backup/staging/atomic replacement, post-start health gate, interrupted recovery, automatic rollback, failure injection + 서버 PC Final E2E |
| 10 | Full E2E + Lobby / Proxy Network | ✅ 완료 | Java four-server/Lobby/routing/reboot E2E + Bedrock real-client routing/return/location behavior를 사용자 실기기 확인으로 PASS. See `DAY10-E2E-REPORT.md` |
| 11 | Operations UX & Fleet Management | ⏳ 예정 | **GSC 4.3 / GSCM 1.1.5 목표**. Full Update Center, startup version check, channel/pin/hold, player-aware update/restart, Geyser/Floodgate/Via policy, 운영 상태 버그 수정 |
| 12 | Final Production Hardening & Closure | ⏳ 예정 | Golden baseline, managed Resource/DataPack, full health/storage/security hardening, trusted builds/offline cache, DR drill, final verifier/E2E/soak, Maintenance Mode handoff |

## Day 8 / Day 9 완료 상태

둘 다 **완료**입니다. "E2E PASS"는 별도의 미완료 상태가 아니라 완료 근거를 뜻합니다.

### Day 8
- Secure Release workflow
- Stable/Beta/Canary
- SHA-256 artifact verification
- Ed25519 signed deployment manifest
- persistent Android release-signing path
- GSC pre-start updater / fail-open
- Wild Technology 0.1.4 실제 업데이트
- Playground 미배포 격리 확인
- 서버 PC finalizer PASS

### Day 9
- 서버 단위 transaction
- backup + staging + atomic replacement
- transaction journal
- post-start health verification
- automatic rollback
- interrupted transaction recovery
- rejected release hold
- known-good fail-open
- failure-injection/self-test
- 서버 PC Final E2E PASS

## Day 10 현재 경계

확인된 실제 Java E2E:
- public Java alias -> Lobby
- Lobby -> Wild / Playground / Other
- `/lobby`
- 서버별 이전 위치 복원
- Windows reboot 후 Velocity 3개 자동 시작
- public Java TCP readiness

Bedrock 쪽도 2026-10-04 사용자 실기기 확인에서 **정상 작동이 확인되어 PASS**로 닫습니다. 이 PASS는 사용자 확인 결과이며 assistant가 직접 클라이언트를 실행한 것으로 기록하지 않습니다.

따라서 Day 10은 Java + Bedrock 범위 모두 완료입니다.

## Day 11 고정 목표

목표 버전:
- GSC **4.3**
- GSCM **1.1.5**

범위:
- GSC/GSCM 실행 시 최신 **검증된** 빌드 확인
- GSC 자체 업데이트 흐름
- GSCM Android 업데이트 흐름 및 iOS 배포 제약에 맞는 업데이트 안내
- GSC Full Update Center / GSCM remote controls
- Stable/Beta/Canary, pin, hold, dry-run
- next-start / next-restart / maintenance-window
- player-aware update/restart
- 자체 컴포넌트 update 상태/이력/rollback
- Geyser/Floodgate/ViaVersion/ViaBackwards 업데이트 정책 통합
- Paper는 별도 호환성/승인 정책으로 관리
- 업데이트 진행률, 실패 이유, rollback 결과, notification/audit

운영 버그 수정:
- RCON이 실제 사용 가능한데 `관리 제한`으로 뜨는 오탐
- 정상 종료 후 `자동 복구 중`으로 보이는 상태 오류
- GSC 콘솔의 의도적 `stop`도 `desired_running=false`로 처리
- 원칙: 의도적 종료 -> OFFLINE, 실제 crash -> RECOVERING -> 자동 재시작

## Day 12 고정 목표

Day 12는 **Final Production Hardening & Closure**이며 이 프로젝트의 마지막 제작 milestone입니다.

- 12.0 Golden Baseline / final freeze
- 12.1 ResourcePack / DataPack managed deployment
- 12.2 전체 구성요소 update inventory / last-known-good / rollback
- 12.3 Whole-system read-only health check
- 12.4 backup retention / disk guard / log lifecycle
- 12.5 SBOM / provenance / dependency / secret / security hardening
- 12.6 trusted/reproducible release chain
- 12.7 shared artifact cache / offline known-good operation
- 12.8 disaster-recovery drill + Recovery Kit
- 12.9 GSC/GSCM final UX cleanup
- 12.10 read-only Final Verification tool
- 12.11 Java/Bedrock/GSCM final live E2E
- 12.12 extended soak test
- 12.13 Stable final release + Maintenance Mode handoff

세부 안전 조건과 완료 Gate는 [DAY12-PLAN.md](DAY12-PLAN.md)를 단일 기준으로 사용합니다.

## 최종 완료 원칙

1. CI 실패 commit은 배포되지 않는다.
2. 검증되지 않은 artifact는 stable에 들어가지 않는다.
3. 인터넷/다운로드 장애가 서버 시작을 막지 않는다.
4. 교체 중 중단되어도 이전 정상 상태로 복구할 수 있다.
5. 새 버전 health 실패 시 rollback할 수 있다.
6. 서버별 설치 버전/정책을 GSC/GSCM에서 확인할 수 있다.
7. 배포/rollback/audit 이력이 남는다.
8. 자체/외부 업데이트 정책을 분리한다.
9. Android/iOS 플랫폼 제약을 각각 지킨다.
10. 운영자가 JAR을 직접 복사하는 작업을 최소화한다.
