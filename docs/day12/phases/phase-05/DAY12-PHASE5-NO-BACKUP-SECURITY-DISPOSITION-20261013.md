# Day 12.5 — 현재 보안 게이트·표준사용자 부재·복구백업 삭제 결론

**2026-10-13 KST · PR #53 검토 전용 · 결론 `LIVE_EFFECTIVE_ACCESS_UNVERIFIED` · `FINAL_STABLE_BLOCKED`**

## 핵심 운영 사실

- Windows 서버 PC에 **별도의 표준 사용자 계정이 없다고 운영자가 확인**했고, 기존 실제 검사에서는 `BLOCKED_FULL_OR_UAC_FILTERED_ADMIN_TOKEN`으로 **루트 유효 권한을 검사하지 못함**. 이는 표준 사용자의 접근 **허용 또는 거부 증거가 아님**. 반복 실행하거나 관리자 토큰 결과를 표준 사용자로 바꾸지 않음.
- 실서버 읽기 전용 범위 검사에서 약 **14,304개** 객체(11,989 파일/2,315 디렉터리)를 조사하고 **특별 보호 6개 파일**의 WRITE-Allow 주체를 SYSTEM/Administrators 범주에서 관측했다. 6개 파일의 직접 Allow 제한은 프로그램 데이터 **루트·Runtime 폴더**와 자식 파일 전체의 실효 AccessCheck를 뜻하지 않음.
- GSC/StatusAgent 트리 루트와 일부 런타임 폴더에는 **상속된 BUILTIN\\Users 생성/쓰기 Allow ACE** 관측. 표준 사용자 토큰·Mandatory Integrity·UAC/deny/상속/서비스 계정·프로세스 로딩 경로를 결합한 **유효 쓰기 가능성은 아직 미확정**.
- 기존 Windows ActiveStore 방화벽 검토에서 광범위 Allow **38개 후보**(전체 269개 Allow 중)를 탐지했고, 후보 이름/서비스 용도가 모두 입증된 상태가 아님. **후보=실제 포트 노출·해킹 증명 아님**, 그러나 전체 정책 PASS도 아님. 이미 수행한 LAN/Tailnet 원격 접근 0/8, 실서버 Native IPv4 Paper Java/RCON 6/6 루프백·PID 확인은 유의미한 별도 방어층 증거다.
- **운영자의 2026-10-13 추가 고지:** 이전에 Golden 등 검사 기준을 충족했던 **서버 파일 백업을 저장공간 부담으로 삭제**. 현재 복구 가능한 서버월드·GSC 설정 스냅샷의 존재가 입증되지 않음. 기존 ACL 보안디스크 아카이브 기록과 **서버월드 백업의 삭제 여부는 서로 다른 자산**이므로 구분하되, 현재 변경 후 완전 원복 능력은 별도 증명이 필요.

## GitHub CI로 검증한 것 / 못한 것

| 분류 | 확보된 증거 | 결론 |
|---|---|---|
| 원자적 파일 쓰기·백업·서명·롤백 소스 | GitHub Windows Go + 보안 CI, 재현성·표준사용자 synthetic 격리 픽스처 | **격리 CI 기능 PASS** |
| 6개 보호 파일의 ACL 관측 | 관리자 트리 기준 실서버 READ_ONLY 결과 | **해당 파일 범위 조사 완료** |
| 실제 GSC 루트 표준 사용자 CreateFile/AddDirectory 거부 | 적절한 표준 사용자 토큰이 없고 기존 실기기 검사 BLOCKED | **NOT TESTED** |
| GSC 루트·하위 ACL 상속 변경과 전체 원복 | 운영 승인 검증된 복구 경로 없음 | **NOT APPLIED / NOT VERIFIED** |
| WFP effective filtering, 모든 overlay/interface 정책 | 광범위 Allow 후보/주소스코프 단서만 확인됨 | **SECURITY_REVIEW_OPEN** |
| 최종 서명 Stable / 실제 서버 적용 | `FINAL-RELEASE-GATES.json` 엄격 게이트 미통과 | **BLOCKED** |

## 빠른 마감에 필요한 정확한 단계 (실행 전 조건)

1. **저장공간을 더 쓰는 백업·계정 만들기·ACL 권한 제거·방화벽 규칙 전체 제거를 자동 실행하지 않음.** 이미 수집한 12.5/12.10 보고서를 그대로 재활용.
2. 별도 표준 사용자 계정이 없다는 사실을 **영구 예외 PASS**로 처리할 수는 없음. 향후 보안 정책 소유자가 검토하는 별도 상호 동등한 실제 Windows 권한 증거 또는 허용 가능한 위험 수용 기준이 필요한 상태. 이 결정은 현재 자동화가 대신 내리지 않음.
3. 실운영 GSC 루트·ProgramData·Runtime·업데이터/클라이언트 쓰기 주체, 상속된 Users ACE의 정확한 출처, 최소 삭제 범위와 서비스 손상 위험을 검토. ACL 변경은 승인 대상별 **전후 SDDL/owner/rollback** 검증이 가능한 경우만 허용.
4. **현재 복구 자산이 검증되지 않은 상황에서는 12.5 실운영 ACL/방화벽 패치, 12.7 운영 오프라인 기동, 12.11 운영 Canary apply/rollback을 실행하지 않음.** 분리된 폐기 가능 Windows CI·테스트 장비에서 먼저 검증.
5. 소규모 서버를 계속 운영하는 **현행 수동 Stable GSC 4.5.1 / GSCM 1.5.1+151 릴리즈**는 그대로 유지하되, 미병합 PR #53이 이미 운영에 적용됐다고 주장하지 않음. 최종 자동 Stable은 생략된 필수 보안·복구 게이트를 정확히 판정하기 전까지 보류.

**다음 운영자 결정이 실제로 필요한 지점:** 복구·롤백의 **실행 가능한 별도 저장 공간 또는 테스트 전용 Windows 환경**이 있는지 여부. 이것이 없다고 해도 기존 8시간 실호스트 안정성 PASS와 Java/RCON Native 6/6 PASS는 취소되지 않음.

증거: [실서버 12.7 최신 차단/백업 삭제 경위](../phase-07/DAY12-PHASE7-LIVE-READINESS-20261013-2323.md), [서명 Canary 별도 결론](../phase-11/DAY12-PHASE11-NO-BACKUP-CANARY-REVIEW-20261013.md), [최종 Fast Track](../../DAY12-STABLE-FAST-TRACK-20261013.md), [Day12 보안 통합 3-AI 검토](DAY12-SECURITY-INTEGRATION-REVIEW-20261012.md).
