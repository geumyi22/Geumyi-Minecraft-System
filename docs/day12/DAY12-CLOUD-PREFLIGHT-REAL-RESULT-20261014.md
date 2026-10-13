# Day12 클라우드 복구 사전검사 — 실제 서버 결과 (2026-10-14)

**실제 비합성 Windows 검사**, 수집 2026-10-14 01:20:19 KST. 사용자 제출 원본 이름: DAY12-CLOUD-PREFLIGHT-SHARE-ONLY-THIS.json; **SHA256** 66d2ca279899fd00c2261fd63d3fd5876dd5fac5de8ee1354ad4fdd323db1b81. 원본은 GitHub에 업로드하지 않음. 읽기 전용, 서버·월드·백업·서비스·방화벽·ACL·클라우드 업로드 변경 없음.

## 정확히 확인된 사실

- 결과: **BLOCKED_DISCOVERY_REVIEW_REQUIRED** (정상적인 fail-closed).
- GSC 설정 프로필 **4개**: wild, playground, other, lobby. 세 온라인 대상 서버 루트 디렉터리를 해당 스크립트 실행 계정에서 **0/3 확인**. 차단 코드: ACTIVE_SERVER_ROOT_UNVERIFIED_WILD, ACTIVE_SERVER_ROOT_UNVERIFIED_PLAYGROUND, ACTIVE_SERVER_ROOT_UNVERIFIED_LOBBY. **실제 서버 파일이 없는지, 권한/경로/링크/설정 해석 문제인지 미확정**. 이전 온라인 Native IPv4 Java/RCON 6/6 소유권 확인은 별도 유효한 당시 증거.
- 기타 Paper는 운영자가 **의도적으로 OFFLINE**이라고 명시. 이 스크립트는 실제 Other 프로세스 확인/기동 안 함.
- Google DriveFS 프로세스 **observed true**, Google Drive 대상 폴더에 선택 불가 차단 코드는 없음. 그러나 **클라우드 계정·업로드·잔여 용량까지 증명한 것 아님**.
- OneDrive 프로세스 **observed true**, 선택 경로 확인 실패: **ONEDRIVE_FOLDER_NOT_SELECTED_OR_UNREACHABLE**; Windows OneDrive 환경 경로 일치 false.
- 실제 남은 Google 2TB/OneDrive 1TB 저장 공간 미검증, 암호화 아카이브 생성 **false**, 실제 클라우드 업로드 **false**, 월드 저장 정합성 **false**, 복원 시험 **false**, 최종 서명 Stable 허용 **false**.

## 왜 같은 검사를 그냥 반복하지 않는가

GSC 서버 루트 0/3은 직접 GSC config path와 path_file, 접근 권한, reparse/junction, %환경변수% 확장 문제 중 무엇인지 **기존 요약에 구분 정보가 없다**. OneDrive 앱이 실행 중인데 폴더를 선택하지 못한 정확한 원인도 미확정. 과거의 Golden 4/4 백업은 저장공간 때문에 삭제됐으므로 현재 복구 가능하다고 취급하지 않는다.

## 보완한 한 번짜리 검사 방식

- 새로운 Windows READ-ONLY 진단은 서버 설정의 직접 경로 / path_file이 열리지 않으면 **GSC Host 자신의 localhost GET /api/settings (8790)** 를 보조 증거로 확인. 서비스가 이미 해석한 디렉터리 사용 가능 여부만 메모리 내 검사하고 공유 JSON에는 경로를 넣지 않음. GET이 401/403이면 ACCESS_DENIED로 기록할 뿐 인증을 우회하지 않음.
- 사용자가 OneDrive 폴더를 다시 선택할 수 있으며, Windows OneDrive 환경변수가 정확히 한 개의 실제 폴더를 가리킬 때는 명시적 **Y 확인**으로 선택 가능. 실제 로그인 계정과 동기화 상태는 검증 전까지 불확실.
- 새 결과에는 프로필별 root_resolution_method, GSC GET 접근 상태, 동일한 이유 코드만 기록. 실제 월드 원본 경로/사용자 계정/암호/API 키 등은 전송하지 않음.
- 테스트용 Windows CI는 PowerShell 5.1 파싱, 합성 정상/차단 경로, 실제 Windows 루트 폴더로 GSC GET fallback 흉내내기를 포함. CI PASS만으로 실서버 경로 PASS 선언하지 않음.

**요청할 다음 작업:** 보완된 클라우드 경로 진단을 서버 PC에서 한 번 실행하여 새로운 SHARE-ONLY-THIS.json만 전달. 8시간 테스트, Native 6/6 검사, 과거 12.7 정책/백업 조회는 반복하지 않음. 기타 OFFLINE 유지.

**엄격한 Day12 최종 서명 Stable 게이트**는 BLOCKED. 실제 새 복구 아카이브의 정합성·암호화·클라우드 전송 완료·독립 다운로드·실제 복원 가능성 확인 전에는 운영 재시작, ACL/방화벽 변경, Canary 설치·롤백을 하지 않음.

관련: [Cloud 복구 계획](DAY12-DUAL-CLOUD-RECOVERY-PLAN-20261014.md) · [클라우드 검사 소스](../../tools/day12/cloud/) · [Day 1~12 마스터](../PROJECT-DAY1-12-MASTER-STATUS-20261013.md).
