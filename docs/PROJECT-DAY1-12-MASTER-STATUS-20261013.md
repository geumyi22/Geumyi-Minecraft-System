# 금이 마인크래프트 시스템 — Day 1~12 상세 통합 현황

**갱신: 2026-10-13 KST · 현재 마스터 현황 / 복구 근거 인덱스 · Draft PR #53 · 운영 데이터 변경 없음**

이 문서는 사용자 요청에 따라 **각 일차 완료의 의미**, **Day12 단계별 상태**, **현재 서버 상태와 릴리즈 상태**, **GitHub 문서 우선순위**를 한곳에 모았습니다. 원본 일차 번호와 완료 선언의 기준은 [DAY-TIMELINE.md](../DAY-TIMELINE.md)이며, 본 문서는 그 기록을 변경하지 않고 **최신 상황을 덧붙이는 인덱스**입니다. 일부 오래된 계획/보고서의 `IN PROGRESS`·`PENDING`은 작성 당시의 스냅샷이며 최신 운영 결론과 다를 수 있습니다.

## 0. 지금 핵심 4가지

1. **현재 기타(Other) Paper 서버: 운영자가 의도적으로 OFFLINE이라고 확인**했습니다. 장애/비정상 종료/자동복구 대상으로 오인하지 않습니다. Wild·Playground·Lobby의 **현재** 상태는 본 턴에서 호스트를 직접 관찰하지 않았으므로 확정하지 않습니다.
2. **Velocity 프런트엔드 25567 ≠ 기타 Paper 백엔드의 ONLINE 상태**입니다. 기타가 OFFLINE이어도 Velocity 25567은 LISTEN 중일 수 있습니다. Day12 8시간 모니터의 수정된 배포용 CMD는 `-ExpectedOtherBackendState OFFLINE`을 명시하며, 25567은 참고값으로 기록하고 필수 TCP 25565/25566/8787만 판정합니다. 실제 Other OFFLINE은 운영자 선언이며 스크립트가 Paper 프로세스를 직접 증명하는 것은 아닙니다.
3. [**이미 공개된 수동 설치 Stable**](https://github.com/geumyi22/Geumyi-Minecraft-System/releases/tag/system-2026.10.11-stable-gsc451-gscm151)은 **GSC 4.5.1 / GSCM 1.5.1+151**입니다. 최종 실기기 확인 **기준선**은 GSC **4.3.8** / GSCM **1.1.5+117**이었습니다. 어떤 실행 파일이 오늘 서버에 설치·로드됐는지는 이 문서만으로 알 수 없습니다.
4. [**Day12 보안 통합 Draft PR #53**](https://github.com/geumyi22/Geumyi-Minecraft-System/pull/53)은 **미병합/미배포**입니다. 2026-10-13 실제 호스트 **8시간 연속 계측은 범위 한정 PASS**로 확보했습니다([보고서](day12/phases/phase-12/DAY12-PHASE12-INSTRUMENTED-LIVE-SOAK-20261013.md)). 새 자동 서명 Stable과 실제 ACL/방화벽 변경은 아직 아닙니다. Release gate는 [FINAL-RELEASE-GATES.json](../FINAL-RELEASE-GATES.json)의 **BLOCKED** 상태를 유지합니다.

## 1. Day 1~12 — 세부 일차별 현재 상태

| 일차 | 목표 | 완료 범위와 실제 근거 | 남은 범위·주의 |
|---|---|---|---|
| **Day 1** | 소스 복구·기준선 고정 | ✅ GitHub 프로젝트 소스/설정/버전 기준선 복구 및 소스 구조 정비 | 과거 원본 바이너리와 재구성 소스를 혼동하지 않음 |
| **Day 2** | CI·초기 컴포넌트 검증 | ✅ GSC·GDS·리소스팩 등 초기 빌드·테스트 체계 수립 | CI 빌드가 오늘의 서버 실행을 증명하지는 않음 |
| **Day 3** | 핵심 플러그인·설정 복구 | ✅ GST **1.1.1 HOTFIX**, StatusAgent **0.5.4**, Technology·Chemistry 및 Wild/Playground 설정과 복구 근거 | 원본 회수/재구성/정적 검증 구별 |
| **Day 4** | 기존 두 서버 실기기 E2E 마감 | ✅ Wild/Playground Paper 26.3, 당시 GSC 4.2.3/GSCM 1.1.2, GST/GDS/StatusAgent 경로 사용자 실서버 확인; **추가 구현 없는 검증 일차** | [Day4 E2E 보고](history/day-04/DAY4-E2E-REPORT.md) |
| **Day 5** | 서버 운영 안정화 | ✅ 정상/강제 종료·시작·재시작, 중복 명령/락, 재연결, Whole Shutdown, 고아 프로세스·상태 표시 운영 검증 | [Day5 안정성 보고](history/day-05/DAY5-STABILITY-REPORT.md) |
| **Day 6** | GSCM 실기기 검증 | ✅ Android+iOS 페어링/인증·HTTP/WS·재연결·제어를 운영자 실기기로 검증 | 최신 1.5.1+151 iOS 서명·재설치를 자동 증명한 것은 아님 |
| **Day 7** | 자동 빌드 기반 | ✅ GSC·StatusAgent·GST·GDS·Chemistry·Technology·리소스팩·GSCM Android/iOS CI/test/artifact 기반 확인 | [Day7 CI 보고](history/day-07/DAY7-CI-REPORT.md) |
| **Day 8** | 보안 릴리즈·자동 업데이트 | ✅ Stable/Beta/Canary, Ed25519 서명 매니페스트·SHA256, 사전 업데이트/fail-open, Wild Technology **0.1.4** 실제 업데이트와 Playground 격리 E2E | [Day8 릴리즈 보고](history/day-08/DAY8-RELEASE-REPORT.md) |
| **Day 9** | 원자적 트랜잭션·백업·자동 롤백 | ✅ staging/backup/journal, health gate, 중단 복구·rollback, 장애 주입·서버 PC Final E2E PASS | [타임라인 원본](../DAY-TIMELINE.md) |
| **Day 10** | Velocity/Lobby 4서버·Java/Bedrock E2E | ✅ Java 프록시→로비→Wild/Playground/Other, 이전 위치 복원, 재부팅 자동 기동; Bedrock 서버 이동/복귀 운영자 실기기 PASS | **당시 실행 성공**이지 현재 Other까지 ONLINE이라는 뜻은 아님. [Day10 E2E](history/day-10/DAY10-E2E-REPORT.md) |
| **Day 11** | GSC/GSCM 운영 UI·전체 업데이트 관리 | ✅ 11.0~11.7, GSC **4.3.8** Client/Host self-update, GSCM **1.1.5+117**, Protection & Recovery 2.0, 운영자 Java/Bedrock 및 GSCM 실기기 확인 PASS | 해당 버전은 **마지막 실기기 검증 기준선**. [Day11 최종 보고](history/day-11/DAY11-FINAL-REPORT.md) |
| **Day 12** | 운영 마감·최종 강화·Stable | ✅ 2026-10-11 **소규모 운영 기준 수락** 및 수동 Stable 공개. Golden 4/4, 캐시 84/84, 플러그인 역사적 SHA 13/13, 반복 기능검증은 수락 범위에서 닫음. 추가 보안 소스/CI 및 실제 GSC 4.5.1 격리 Paper 장애 복구 테스트 | **엄격한 최종 서명 Stable**은 현재 12.5/12.7/12.10/12.11 및 12.12 공식 게이트 검토 때문에 미완료. 아래 세부 단계 참조 |

> ✅ **완료**는 해당 일차의 *당시 승인된 범위* 종료를 뜻합니다. 정식 자동 Stable의 모든 현재 조건이 PASS라는 뜻이 아닙니다. 2026-10-11 소규모 서버 운영 종료 결정 후 2026-10-13 사용자가 **8시간 시험 포함 남은 정식 Stable 검증을 다시 승인**했습니다. 따라서 이 시험을 취소하거나 과거 사용자 면제 결과를 *신규 실험 PASS*로 둔갑시키지 않습니다.

## 2. Day 12.0~12.13 세부 진행표

> **중요: 2026-10-13 현재 백업 가용성 변경.** 운영자에 따르면 과거 통과했던 **서버 파일 백업은 디스크 용량 때문에 이후 모두 삭제**했습니다. 따라서 아래 **12.0B Golden 4/4와 12.7 84/84**는 *과거 검증 이력*이며, 지금 복구 가능한 전체 서버 백업이 남아 있다는 증거가 아닙니다. 현재 보호된 실제 놀이터 복구 체크포인트 **미확인**, 새로운 대용량 전체 백업 **자동 생성하지 않음**. **데이터 손실 위험이 있는 재시작·배포·ACL 변경은 복구 경로 확보 전 보류**합니다. GitHub 격리 CI와 읽기 전용 리뷰는 계속할 수 있습니다.


| 단계 | 실제로 확보된 증거 · 완료 내용 | 현재 판정 · 추가 필요 |
|---|---|---|
| **12.0A** 기준선 | 실제 호스트 READ-ONLY 초기 READY 보고 | ✅ 수락된 스냅샷, 최신 실행 버전은 재확인 필요 |
| **12.0B** Golden | 실제 FULL Golden **4/4 보호 백업** 확인 | ✅ 수락. 백업 삭제/압축 재생성 불필요 |
| **12.1** 콘텐츠/팩 | Java/Bedrock 기존 팩·매핑·실제 접속 운영자 확인; 소스 검증/manifest 사전 검사 | ✅ 기존 운영 콘텐츠 수락. 관리형 자동 적용·재배포는 별도 미실행 |
| **12.2** 컴포넌트/출처 | 당시 실설치 JAR **13/13** CI/릴리즈 SHA-256과 추적 일치; Lobby 두 alias도 후속 해결 | ✅ 역사적 설치 출처 확인. 오늘 로드 중인 바이너리 검증은 별개 |
| **12.3** 전체 헬스 | 당시 호스트 검증 **15 PASS, WARN/FAIL 0** | ✅ 당시 건강상태 범위만 PASS. 12.10의 커널 바인딩 증명 대체 불가 |
| **12.4** 저장소·백업·로그 정책 | 실제 dry-run 제거 후보 **0**; 운영자 승인 **NO ACTION** | ✅ 리뷰 종료. 정리 정책을 실제로 자동 설치한 것으로 표시하지 않음 |
| **12.5** 권한·보안 | 실제 Windows 소유자 14,304 객체, 예외 **6개 보호 DACL 파일**의 WRITE 허용 대상은 SYSTEM/Administrators 범주만 관측, 기타 쓰기 주체 0; 보안·SBOM CI PASS | ⚠️ GSC 루트 상속된 광범위 WRITE ACE 여전. 표준 사용자 계정이 **없어** 실제 유효 접근 검사는 `BLOCKED_UNVERIFIED`. 운영 ACL 변경/롤백 증명 별개 |
| **12.6** 서명 릴리즈 체인 | GitHub build/reproducibility/manifest 서명 순서·차단 정책·Android signer 검증 CI | ✅ **CI·설계만** 확인. 최종 자동 서명 Stable 자체는 미발행; iOS IPA는 unsigned |
| **12.7** 캐시·오프라인 기동 | 실호스트 캐시 **84/84**, GSC 4.5.1 + Paper 26.3 격리 CI 업데이트 출처 장애 속 기동 성공. **2026-10-13 23:23 실제 GSC Host 4.5.1 / 놀이터 ONLINE·접속자 0·작업 0** 사전검사 [결과](day12/phases/phase-07/DAY12-PHASE7-LIVE-READINESS-20261013-2323.md) | 🟠 **실서버 실제 오프라인 기동은 미실행**. 확인 필요 원인 정확히 2개: `AUTOMATIC_UPDATE_POLICY_MUST_BE_REVIEWED`, `TARGET_PROTECTED_VERIFIED_FULL_BACKUP_NOT_CONFIRMED`. 실제 백업 부재를 뜻하지 않음. 동일 사전검사 재실행 금지; 복구자산/정책 확인 전 운영 재시작 금지 |
| **12.8** 재해 복구 | 일회용 DR/recovery CI·rollback, 복구 패키지 | ✅ 합성/격리 CI 검증. 보호된 실제 월드 전체 복구는 실행하지 않음 |
| **12.9** 운영 UX | GSC 데스크톱/GSCM Android 콘솔 UI 정상 운영자 수락, iOS 상태/재접속 수락 | ✅ 운영 UI 범위 수락; 최신 수정 iOS IPA 기기별 서명·설치 증거는 예외 |
| **12.10** 백엔드·포트 보안 | 기존 LAN/Tailnet 양 IP 계열 외부 private TCP 접근 **0/8** 보조 증거 및 2026-10-13 **실서버 Native IPv4 Java/RCON 루프백·Paper PID 3쌍/6포트 모두 매칭, 이유 오류 0**. IPv6 owner 조회 정상·매칭 0, 의도적 OFFLINE Other 포트 이상 리스너 0. [실측 상세](day12/phases/phase-10/DAY12-PHASE10-LIVE-OWNER-BIND-20261013.md) | ✅ **온라인 3서버의 6/6 Native 소유권·루프백 실측은 범위 한정 PASS**. ⚠️ OS/방화벽·WFP 전 경로 보안 정책 검토 및 Canonical `backend_ports_private`는 **아직 FAIL/REVIEW**. IPv6 0개 및 Other OFFLINE은 포트 부재로만 제한 해석 |
| **12.11** 통합 E2E | 운영자 기존 Java/Bedrock/GSCM 기능 PASS, 18개 중 **16개 수락/범위별 마감**, #2 호스트 Java 역할 문제 해소; 최신 **GSC 4.5.1 + 실제 Paper 26.3 격리 CI**에서 비정상 종료→RECOVERING→신규 PID 복구 통과 | 🟠 #12 실제 운영서버 crash를 수행한 것은 **아님**; #17 **정식 서명 Canary apply/rollback 실제 스테이징**은 미증명. 사용자 실기기 최종 후보 확인 별개 |
| **12.12** 연속 안정성 | **실호스트 8시간 계측 완료** (2026-10-13 01:35~09:35 KST), 5분 간격 97샘플·최대 간격 5분·관측된 TCP 이상 0·수집 오류 0·Java/GSC 프로세스 교체 0·식별 불가 0. [실제 측정 근거](day12/phases/phase-12/DAY12-PHASE12-INSTRUMENTED-LIVE-SOAK-20261013.md) | ✅ **8시간 TCP/프로세스 모니터링은 실호스트 범위 한정 PASS**. 원본 JSON의 `REVIEW_REQUIRED`/자동 Stable 불허 유지. 기타 의도적 OFFLINE·Velocity 25567 구분, 게임/E2E 및 엄격한 릴리즈 게이트 별개 |
| **12.13** Final Stable | [수동 설치 Stable GSC 4.5.1 / GSCM 1.5.1+151](https://github.com/geumyi22/Geumyi-Minecraft-System/releases/tag/system-2026.10.11-stable-gsc451-gscm151) **기공개** | 🔒 최종 **보안 통합 코드 병합·자동 서명 Stable·Maintenance Mode**는 엄격한 필수 실호스트 게이트 PASS 전 미승인 |

## 3. 2026-10-13 GitHub 최신 엔지니어링 진행

- 통합 저장소 작업 브랜치 **`integration/day12-security-review-20261012`**, PR **#53 Draft/미병합**. 이미 공개된 구버전 수동 Stable에는 해당 PR의 새 보안 코드가 포함되지 않습니다.
- **PR #53 HEAD `5467b01d` 시점 GitHub 7/7 CI 성공**: System CI, Day12 Safety, Security/SBOM, Host Test, Synthetic DR, 8시간 모니터 배포/자체시험, GSC 4.5.1 + Paper 26.3 실제 프로세스 격리 Offline/Crash 복구 2개 테스트.
- **2026-10-13 추가 12.10 실호스트 증거:** [Native 소유권/루프백 바인딩 6/6 실제 보고서](day12/phases/phase-10/DAY12-PHASE10-LIVE-OWNER-BIND-20261013.md), 기타 의도적 OFFLINE; 최종 보안 전체 게이트는 별도 미완료.
- **2026-10-13 추가 실호스트 증거:** 8시간 모니터링 97개 샘플, 연속성 정상, TCP 관측 오류 0, 프로세스 교체 0, 수집 실패 0. [증거·범위·한계](day12/phases/phase-12/DAY12-PHASE12-INSTRUMENTED-LIVE-SOAK-20261013.md). 기존 검사기 사용 결과이며 **새 Other-aware 검사기를 또 8시간 실행할 필요는 없습니다.**
- **이 문서 이후 PR HEAD는 변경될 수 있습니다.** 과거 7/7 성공을 새 커밋의 자동 성공으로 간주하지 않습니다. GitHub Actions는 각 커밋별 완료 여부를 확인하세요.
- Release 결정의 단일 기계 판정 기준: `FINAL-RELEASE-GATES.json` + `tools/day12/validate_final_release_gates.py`. 사람 수락/CI 결과로 다른 실호스트 필수 게이트를 묵시적 PASS 전환하지 않습니다.

## 4. 이 문서를 읽는 순서 · 안전 원칙

| 먼저 볼 문서 | 용도 |
|---|---|
| [저장소 루트 README](../README.md) | 설치 릴리즈 및 코드 구성 |
| [DAY-TIMELINE](../DAY-TIMELINE.md) | **일차 번호·이전 완료 선언의 단일 기준** |
| **이 문서** | **Day별 상세 현재 상태**와 운영·검증·미완료 구분 |
| [Day12 Stable Fast Track](day12/DAY12-STABLE-FAST-TRACK-20261013.md) | 실호스트 필수 검사/배포 순서 |
| [Day12 단계별 문서 목차](day12/INDEX.md) | 원본 검사/후속 경위 조회 |
| [History Day4~11 목차](history/INDEX.md) | 과거 실제 테스트·보고서 |
| [저장소 파일 지도](REPOSITORY-MAP-20261013.md) | 현행 도구/CI/복구/과거 소스 구분 |
| [FINAL-RELEASE-GATES](../FINAL-RELEASE-GATES.json) | 최종 Stable **엄격한 기계 판정** |

**정리 정책:** 과거 문서, 회수 소스, 성공·실패 CI 증거, 서명 릴리즈·태그, 파일/원본 백업·복구 명령은 삭제하지 않습니다. 서명 릴리즈/설치 경로·CI가 직접 참조하는 파일은 이동하지 않습니다. 기존 GitHub Actions 실행 이력을 대량 삭제하지 않고, 마스터 링크와 역할 분류로 탐색 난이도만 낮춥니다.
