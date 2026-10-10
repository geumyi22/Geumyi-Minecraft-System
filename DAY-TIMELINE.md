# Geumyi Minecraft System — Canonical Day Timeline

기준일: 2026-10-11

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
| 11 | Operations UX & Fleet Management | ✅ 완료 | **GSC 4.3.8 live / GSCM 1.1.5+117 live verified**. Phase 11.0~11.7, Client/Host self-update, Protection & Recovery 2.0, Final integrated READ-ONLY E2E, Java/Bedrock real-client smoke 및 마지막 GSCM 2개 device check까지 사용자 확인 PASS. See `DAY11-FINAL-REPORT.md` |
| 12 | Final Production Hardening & Closure | ✅ **소규모 운영 마감 (2026-10-11)** | Wild·Playground·Lobby 공통 기능 운영자 PASS, 기타(Other) 추가 시험 면제, Golden 4/4, cache 84/84, 재해 복구/롤백 일회용 CI 통과. **12.5 실효 보안·12.10 정식 네이티브 보안·12.13 정식 Stable 릴리즈는 미승인**; 소규모 운영 PASS와 정식 Release PASS는 별개. 상세: `PROJECT-CLOSEOUT-2026-10-11.md` |


> **2026-10-11 최종 범위 변경:** 사용자의 명시적 결정으로 Day 12는 소규모 서버 **운영 및 개발 작업 종료**로 마감했습니다. 이 문서 아래에 남은 과거 `Day 12 현재 진행 상태` 상세 항목은 당시 엄격한 **정식 Stable 검증 상태의 역사적 스냅샷**입니다. 그것이 운영 마감 취소를 의미하지 않으며, 거꾸로 운영 마감이 `FINAL-RELEASE-GATES.json`을 자동으로 PASS로 변경하지도 않습니다.

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

## Day 11 완료 상태

Day 11은 2026-10-07 기준 **완료**입니다.

최종 기준:
- GSC **4.3.8 live**
- GSCM **1.1.5+117 live verified**
- Phase 11.0~11.7 완료
- Final integrated READ-ONLY E2E PASS
- Java + Bedrock post-update real-client smoke USER PASS
- 마지막 GSCM 2개 실기기 확인 항목 USER PASS

최종 근거: [DAY11-FINAL-REPORT.md](docs/history/day-11/DAY11-FINAL-REPORT.md)

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

## Day 12 현재 진행 상태

- Day 12: **IN PROGRESS**
- repository/tooling preparation: **✅ verified**
  - Day 12 Safety CI `37670902211`: PASS
  - Security + declared-component SBOM + GSC reproducibility `37670892834`: PASS
  - Synthetic DR + Recovery Kit `37670892599`: PASS
  - installer cleanup 후 System CI `37669908817`: PASS
  - installer Host Test `37669908646`: PASS
- 12.0A real server-PC READ-ONLY capture: **✅ 운영자 READY 보고 (2026-10-09 02:45 KST)**
- 12.0B protected Golden Recovery Checkpoint: **✅ 운영자 PASS 보고 (03:23 KST), 4/4 protected FULL backups**
- 12.1 content / 12.2 inventory / 12.3 health / 12.4 lifecycle / 12.5 runtime security: **⏳ live 확인·적용 대기**
- 12.6 trusted release chain: **✅ repository workflow / 🔒 Stable promotion 차단**
- 12.7 Known-Good Cache: **✅ Build PASS 보고 (03:45 KST, 84 hashed artifacts) / ⏳ offline startup E2E 대기**
- 12.8 synthetic DR: **✅ PASS** (비운영 합성 테스트, 실제 서버 DR과 구별)
- 12.9 installer stale payload cleanup: **✅ source/CI PASS**
- 12.10 final verifier: **✅ 도구·CI 준비 / ❌ 2026-10-09 03:47 KST 실서버 18 PASS / 0 WARN / 1 FAIL** (`backend_ports_private` TCP listener inventory 부재); 최신 TCP bind 진단 도구의 합성 CI는 PASS이나 실제 재검증은 필요
- 12.11 Final live E2E: **⏳**
- 12.12 Soak: **⏳**
- 12.13 Stable + Maintenance Mode: **🔒 BLOCKED until all gates PASS**

참고: 12.0/12.7의 시간·결과는 Day 12 운영자 진행 기록에 근거한 것입니다. 이 저장소의 `FINAL-RELEASE-GATES.json`은 원본 보고서 검토 및 필수 게이트 확인 전까지 fail-closed/PENDING으로 유지합니다.

세부 구분: `DAY12-REPO-PROGRESS.md` / 실행 순서: `DAY12-LIVE-RUNBOOK.md`

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
