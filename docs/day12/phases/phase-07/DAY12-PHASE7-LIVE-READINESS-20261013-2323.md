# Day12.7 — 2026-10-13 23:23 KST 실제 서버 오프라인 기동 사전검사

**대상:** 놀이터(Playground) · GSC Host **4.5.1** · 사용자 제출 `Day12-Offline-Readiness-READ-ONLY(1).json`  
**원본 SHA-256:** `bad5441368398cb59c3bf814336686a345a37c90c42fcadf67a6e57a1392b0bc`. 원본 JSON·API 응답·토큰·로컬 경로·백업 파일명은 GitHub에 커밋하지 않음.  
**실제 수집:** `generated_at=2026-10-13T23:23:59.0245766+09:00`, `synthetic=false`, `read_only=true`.

## 원본 검증 결과 — 차단 두 건

원본 `result=BLOCKED_NEEDS_SAFETY_REVIEW`, `stable_release_allowed=false`. 아래 두 이유만 포함되어 있음:

1. **`AUTOMATIC_UPDATE_POLICY_MUST_BE_REVIEWED`** — `update_policy_nonmanaged=false`. `hold` 또는 `manual` 정책이 확증되지 않았다는 뜻. **실제 policy 원문을 공유하지 않았으므로 관리형(`managed`)으로 단정하지 않음.** 이전 2026-10-10 4.3.8 검사에서도 같은 이유 한 건이 확인됨. 플러그인이 자동 갱신될 가능성을 배제하지 못하므로, 일반 서버를 재시작하며 테스트하거나 권한 없이 정책을 수동 전환해서는 안 됨.
2. **`TARGET_PROTECTED_VERIFIED_FULL_BACKUP_NOT_CONFIRMED`** — 해당 API 응답에서 `protected=true`, `verified=true`, `scope=full`, `trashed=false`를 모두 만족하는 놀이터 백업이 **사전검사에 의해 확인되지 않음**. **물리적으로 백업이 없다는 증명이 아님.** 2026-10-10 4.3.8 검사에서는 이 조건이 통과했고 Day12 Golden 4/4 보호 기록도 존재. 그러나 다른 시점 및 위치의 Golden 결과만으로 **지금 현재 놀이터 복구 가능**을 자동 확정할 수 없음. GSC의 `/api/v4/backups?id=playground`는 현재 GSC 백업/체크포인트 목록이며, API 응답 오류·목록 변화·보호 메타데이터·full scope 차이가 원인일 수 있음. 무엇인지 이 sanitized summary로는 알 수 없음.

## 실제 확인된 정상 전제

| 사전 검사 항목 | 결과 |
|---|---|
| GSC Host Windows 서비스 | **RUNNING** |
| Host 버전 | **4.5.1, 지원 목록 내** |
| 업데이트/운영 Active Jobs | **0건** |
| 놀이터 Fleet 역할 | **정확히 한 개** |
| 놀이터 현재 상태 | **ONLINE** |
| 놀이터 접속자 수 | **0명 확인** |
| 업데이트 단계 | 검사기의 허용 상태에 해당 |
| 명시적 `block_start` | **false** |
| 예상 기타 서버 | 운영자 별도 선언에 따라 **OFFLINE**, 이 시험으로 변경·재검증하지 않음 |

**실제로 수행되지 않은 항목:** 업데이트 서버 접속 장애 발생, 오프라인 Paper 기동, 실제 서버 재시작, Java/Bedrock 게임 클라이언트 E2E, 백업/월드 변경, NIC/방화벽/ACL 변경 모두 **false**. 따라서 **Day12.7 실제 오프라인 기동은 `BLOCKED_NOT_TESTED`**이고, 이 결과는 Minecraft 기동 실패가 아니다. 동일한 read-only preflight를 즉시 다시 실행해도 기존 정책/백업 조건이 바뀐 근거가 없으면 정보가 추가되지 않는다.

## 다음 작업 원칙 (실기기 반복 최소화)

- **재검사 금지:** GSC 4.5.1 Host/Playground ONLINE/0 players/0 jobs, 84/84 cache, 4/4 Golden 역사적 기록은 현 단계에서 다시 수집하지 않음.
- **원인 분리만 필요:** `/api/v4/backups?id=playground`의 보호된 verified full 항목이 왜 확인되지 않는지 GSC 보호·복구 UI의 기존 항목 **읽기 전용** 조회/운영자 확인으로 판별. 새 백업을 무작정 만들지 않음(특히 full backup은 서비스 정지가 요구될 수 있음). BackupInfo의 보호 속성은 별도 체크포인트/보호 메타데이터와 연관됨.
- **안전한 테스트 우선:** 이미 [Windows 격리된 현재 GSC 4.5.1 + 실제 Paper 26.3 오프라인 업데이트 서버 장애 시험](https://github.com/geumyi22/Geumyi-Minecraft-System/actions/runs/38278642690)에서 Paper 재기동 및 기존 JAR 보존이 **격리된 환경**에서 입증됨. 이를 실서버 완전 오프라인 부팅 PASS로 격상하지 않되 중복 테스트도 요구하지 않음.
- **차기 실험:** 보호 복구자산, 네트워크 영향 범위, 업데이트 정책과 롤백 경로를 확정하기 전에는 프로덕션 놀이터 네트워크 차단/재시작/자동 업데이트 정책 변경을 수행하지 않음. 분리된 격리 테스트 또는 승인된 정확한 대상 maintenance 계획부터 완성.
- **12.11로 병행 진행:** Canary 적용·실제 롤백을 격리 Windows 클라이언트/테스트 Host에서 수행할 수 있는지 기존 서명 초안/키/아티팩트 및 롤백 조건을 먼저 검증. 정식 Stable 여부는 별도.
- **12.5:** 별도 Windows 표준 사용자 계정이 없으므로 `BLOCKED_UNVERIFIED` 보존. 관리자 토큰 검사를 표준 사용자 증거로 위조하지 않음.

**현재 단계 판정:** 실제 12.7 사전 안전성은 **`BLOCKED_NEEDS_SAFETY_REVIEW`**; 원인 2개는 정확히 보존. `FINAL-RELEASE-GATES.json`의 `phase_12_7_offline_known_good_startup`은 여전히 `PENDING_LIVE`, `stable_release_allowed=false`. 기존 수동 GSC 4.5.1/GSCM 1.5.1 Stable은 보존되며 PR #53은 Draft.
