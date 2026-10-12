# 금이 마크 서버 GitHub — 2026-10-13 통합 저장소 지도

> **파일 삭제나 위치 이동 없이 검색·운영 흐름을 정리한 최신 목차입니다.** 과거 2026-10-11 대규모 GitHub 정리 기록은 [PROJECT-CLOSEOUT-2026-10-11.md](../PROJECT-CLOSEOUT-2026-10-11.md)에 역사적 사실로 남겨 둡니다. 그 당시 실행 808개/워크플로 18개 등의 숫자는 **오늘의 실시간 총수라고 간주하지 않습니다.**

## 1. 이 순서로 접근

| 필요한 작업 | 단일 권장 시작점 | 보조 원본 |
|---|---|---|
| 지금 프로젝트 상태 / Day 1~12 완료 현황 | [Day 1~12 마스터 현황](PROJECT-DAY1-12-MASTER-STATUS-20261013.md) | [DAY-TIMELINE.md](../DAY-TIMELINE.md) |
| 다운로드할 수동 Stable | [GSC 4.5.1 / GSCM 1.5.1+151 공개 릴리즈](https://github.com/geumyi22/Geumyi-Minecraft-System/releases/tag/system-2026.10.11-stable-gsc451-gscm151) | [README](../README.md), [VERSION-MATRIX](../VERSION-MATRIX.md) |
| 정식 서명 Stable 남은 조건 | [Stable Fast Track](day12/DAY12-STABLE-FAST-TRACK-20261013.md) | [엄격한 JSON 게이트](../FINAL-RELEASE-GATES.json), [최종 E2E](../FINAL-E2E-REPORT.md) |
| 실제 호스트 검사/원인 분석 | [Day12 세부 인덱스](day12/INDEX.md) | [Day12 이전 원본 로그](../DAY12-REPO-PROGRESS.md) |
| 과거 Day 4~11 | [History Index](history/INDEX.md) | [당시 원본 일차보고](../ROADMAP.md) |
| 복구·장애·인프라 | [Reference Index](reference/INDEX.md) | [운영 Index](operations/INDEX.md) |
| CI 로그·실행 결과 | [Actions](https://github.com/geumyi22/Geumyi-Minecraft-System/actions) | [PR #53](https://github.com/geumyi22/Geumyi-Minecraft-System/pull/53) |

**읽기 우선순위:** ① 마스터 현황 → ② 사용자 작업에 맞는 운영/코드 목차 → ③ 필요할 때 원본 CI/보고서. `DAY12-PLAN.md`, `DAY12-REPO-PROGRESS.md`는 중요한 상세 이력이며, 오래된 기록을 최신 결론으로 혼동하지 않습니다.

## 2. 코드를 탐색하는 지도

| 디렉터리 | 내용 | 관리 원칙 |
|---|---|---|
| `GSC/ServerCenter/` | Windows GSC Host/Client, 업데이트/백업/원자 교체/로컬 인증 Go 소스 | 최신 실운영 빌드와 승인된 릴리즈는 구분 |
| `GSC/StatusAgent/` | 서버 상태 Java Agent | 원본·재구성 소스, 검증 근거 유지 |
| `GSCM/` | 모바일(Android/iOS) 원격 관리 UI·빌드 | Android 서명 릴리즈와 **unsigned iOS IPA** 별도 표기 |
| `Plugins/` | GST, GDS, Technology, Chemistry, Network, Lobby 등 Java 플러그인 | 설치/원본/재구성/CI provenance 보존 |
| `Servers/` | 4서버 역할별 보존된 설정·복구 자료 | 사용자 PC의 실제 월드 및 현재 실행 상태로 오인 금지 |
| `ResourcePacks/` | Java·Bedrock 팩·Geyser 매핑 | 압축 자산과 사용자 운영팩 간 현재 동일성은 별도 검증 |
| `Network/` | Velocity/Lobby/Java·Bedrock 연결 관련 도구·설정 | 프록시 프런트엔드 vs 실제 Paper 백엔드 분리 |
| `deploy/` | 서명/프로모션 정책·출처·Day12 근거 ledger/manifest | 필수 게이트 없이 promote/Apply 금지 |
| `tools/day12/` | Day12 운영자 검사기·CI 검증 스크립트 | READ_ONLY와 변경형 APPROVAL_REQUIRED 도구 구별 |
| `.github/workflows/` | 현재 CI/실제 빌드·릴리즈·안전 게이트 정의 | 사용 중인 워크플로를 무작정 병합·삭제하지 않음 |
| `docs/history/` | Day 4~11 검증 원본 | 원본 파일명·맥락 유지 |
| `docs/day12/` | Day12 phase별 계획·실서버·보안/품질 검증 기록 | 주요 현황은 마스터 문서에 최신 링크 |
| `docs/archive/` | 보관한 CI 워크플로 등 과거 문서 | 증거 복원성을 위해 보존 |

## 3. CI 워크플로 용도별 구분 (소스 파일 자체는 이동하지 않음)

| 유형 | 워크플로 | 실환경/테스트 구분 |
|---|---|---|
| **일반 빌드·호환성** | `system-ci.yml`, `android-build.yml`, `ios-build.yml`, `gscm-day10-ci.yml`, `day11-host-test-package.yml` | 빌드·러너 실험. 실제 기기 설치 확인과 구별 |
| **보안·무결성** | `day12-safety-ci.yml`, `day12-security-ci.yml`, `day12-phase6-release-chain-audit.yml`, `day12-scoped-evidence-ledger.yml` | 격리/정적 CI. 라이브 ACL/네트워크 증거 대체 불가 |
| **장애·복구·재현성** | `day12-dr-ci.yml`, `day12-phase7-disposable-real-paper-offline-source.yml`, `day12-phase11-disposable-gsc-paper-crash-recovery.yml`, `day12-current-head-disposable-e2e.yml` | **일회용 Windows 테스트 환경**; 운영 서버 충돌·복원 아님 |
| **8시간 테스트 도구** | `day12-stable-soak-kit.yml` | 도구의 Windows CI 및 ZIP 생성. **실제 8시간 검사는 운영 PC 실행 필요** |
| **기능 회귀/운영 준비** | `day12-bedrock-crlf-regression.yml`, `day12-console-live-refresh-ci.yml`, `day12-operator-kit.yml`, `day12-final-gate.yml` | 각 워크플로 설명에 적힌 범위만 입증 |
| **출시·승인** | `day12-final-release.yml`, `day8-release.yml` | 릴리즈·서명·태그·배포: 승인과 엄격한 증거 요건 필요 |

다른 보조 워크플로도 존재합니다. 위 표는 **중요한 동선을 안내하는 대표 목록**이지 활성 워크플로를 삭제해야 한다는 목록이 아닙니다. 사용 중인 경로의 원본을 변경할 때마다 CI로 재검증해야 합니다.

## 4. 현재 운용 상태와 CI 가정

- 사용자 최신 운영 선언: **Other Paper OFFLINE**. 과거 Day 10 E2E에서 Other 정상 이동이 확인된 것과 양립 가능합니다. 당시 다른 시점의 증거입니다.
- Velocity 25567은 **프록시 프런트엔드**이므로 기타 Paper 중지의 직접적인 지표가 아닙니다. 기타 프런트엔드가 열린 사실로 Other Paper가 실행 중이라고 주장하지 않습니다.
- `tools/day12/Start_Day12_8H_Soak_READ_ONLY.cmd`는 **기타 OFFLINE 기대 상태**로 실행하며, 25567은 참고 관찰이고 나머지 필수 로컬 TCP는 유지합니다. 기대 상태는 명시 입력되어야 하며 결과는 항상 REVIEW_REQUIRED입니다.
- 12.10의 native Java/RCON PID·바인딩 증거에서 기타 Paper가 실제 OFFLINE이라면 해당 Paper 리스너의 **부재 자체를 실패로 다루지 않는 검증 범위**와, 실행 중인 인스턴스만의 실효 보안 검증을 구분합니다.
- 12.5 실제 표준 사용자 계정이 없어 확인 불가. 권한 검사를 인위적으로 통과시키기 위해 새 계정을 만들거나 프로덕션 ACL을 무조건 변경하지 않습니다.

## 5. 무엇을 절대 함부로 지우지 않는가

- Git 태그, 공개 Stable/베타 릴리즈, 검증 SHA·SBOM·서명/체크섬, 실제 윈도 PC Golden 백업, 테스트/복구 근거.
- `FINAL-*.json` 및 자동 배포 게이트 검사기가 참조하는 고정 파일 경로.
- 기록된 CI 실행/아티팩트 증거. 이전에 정리했던 CI 수를 무조건 다시 줄이지 않습니다.
- `docs/archive/workflows/`의 역사적 CI 소스 및 `docs/history/`의 원본 E2E 보고서.
- 이미 작동하는 서버의 사용자 설정·팩·world를 GitHub 문서 정리 목적으로 수정하지 않습니다.

**정리 방식:** 하나의 최신 현황/하나의 코드·문서 지도/분야별 하위 원본 유지/README 바로가기, 그리고 CI 결과가 바뀔 때만 명확한 최신 검증 갱신.
