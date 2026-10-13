# Day12 — Google Drive 2TB + OneDrive 1TB 이중 클라우드 복구 설계 (2026-10-14)

> **상태: `PREFLIGHT_KIT_CI_PASS` / `NO_LIVE_BACKUP_YET` / `STABLE_RELEASE_BLOCKED`**
>
> 운영자 고지: Google Drive **2TB**, OneDrive **1TB** 구독 및 **서버 PC에서 두 클라우드 로그인·업로드 가능**. 구독 총 용량과 실제 잔여 용량, 현재 선택된 로컬 마운트, 동기화 전송 완료는 별도로 검증되어야 한다. 서버 PC의 **과거 서버 파일 백업들은 저장공간 때문에 운영자가 모두 삭제했다고 확인**. 과거 Golden 4/4는 당시 무결성 확인 이력이지 현재 복구본 존재 증거가 아니다. **Other Paper는 의도적 OFFLINE**으로 유지한다.

## 1. 설계 목표와 우선순위

| 등급 | 백업 내용 | Google Drive | OneDrive | 가용성 조건 |
|---|---|---|---|---|
| **P0 — 필수** | GSC 설정·Host/Client 설치 복원정보·운영 스크립트·핵심 보안 설정의 **암호화된 시점 일치 스냅샷** | 최신 1개 이상 | 같은 버전의 독립 복사본 1개 이상 | 복구된 GSC Host/Client 버전/설정·암호 검증. 실제 비밀번호/토큰은 보고서에 포함하지 않음 |
| **P1 — 필수** | Wild·Playground·Lobby 월드·Paper/Velocity 및 플러그인·Geyser/RCON 설정 등 **서버 운영 전체를 복원 가능한 정합성 있는 단위** | 용량 검토 후 | 1TB 실제 남은 용량에 맞으면 중복 보관, 아니면 중요 월드·설정만 선별 | 기존 실행 중 월드를 로컬 동기화 폴더에 직접 지정하지 않음. 정상 저장/일시 중단/오프라인 스냅샷 조건 충족 |
| **P2 — 선택** | Other 월드·설정 | 현재 OFFLINE 상태 그대로 백업 검토 | 가용 용량에 따라 핵심만 보관 | Other를 검사/백업 때문에 켜지 않음 |
| **P3 — 선택** | 오래된 로그·임시 배포물·이중 JAR 캐시 | 긴급 복구 우선순위 낮음 | 사용 공간에 따라 보류 | 신규 백업이 무결성·복원 검증되기 전 원본/기존 보호자료 임의 삭제 금지 |

**용량:** 2TB+1TB는 *사용자가 구독한 한도*이지 업로드 가능한 남은 공간 합계 3TB를 뜻하지 않는다. 두 클라우드의 중복 복사에는 각 서비스의 용량이 **별도로** 필요하며, Windows DriveFS/OneDrive의 디스크 캐시·가상 드라이브·파일 스트리밍 환경에 따라 로컬 임시 사용량이 발생할 수 있다.

## 2. 단계 A — 현재 실제로 준비한 READ-ONLY 사전검사

**도구:** `tools/day12/cloud/Day12_Cloud_Recovery_Preflight_READ_ONLY.ps1`와 `RUN_Day12_Cloud_Recovery_Preflight_READ_ONLY.cmd`. 전용 GitHub Windows CI에서 PowerShell 5.1 구문·합성 정상/차단 케이스·서버 경로와 클라우드 폴더가 겹치지 않도록 하는 조건·공유 JSON 불변조건을 검증한다.

- Windows 폴더 선택기에서 사용자가 Google Drive 내 드라이브와 OneDrive 실제 폴더를 **명시 선택**. Windows 프로세스/환경변수는 힌트이며 실제 계정 소유권 또는 업로드 완료 증거는 아님.
- `%ProgramData%\GeumyiServerCenter\server.json`에서 ID와 **`path` 또는 `path_file` 간접 서버 루트**를 원문 노출 없이 확인. 세 온라인 역할의 루트 존재와 기타 역할 설정 여부 관찰.
- 응답에는 중요한 사용자 정보(절대 경로, 사용자명, API 키, 인증 토큰, 실제 config·월드 내용)를 넣지 않는다.
- 이 단계는 서버 중지·재시작/월드 백업·클라우드 복사·로그인 세션 변경·폴더 생성·네트워크/ACL 변경 **모두 하지 않음**.
- 정상 종료하더라도 보고서 `DESTINATIONS_AND_SOURCE_DISCOVERED_REVIEW_REQUIRED`은 **복구본 생성 PASS가 아님**. `BLOCKED_DISCOVERY_REVIEW_REQUIRED`는 경로·프로세스·서비스 추가 정보가 필요하다는 뜻이며 현재 월드 손상을 주장하지 않음.

## 3. 단계 B — 암호화·정합성 있는 백업 (사전검사 결과 받은 후만 실행)

1. **데이터보호 전제:** Minecraft 월드와 GSC 설정에는 사용자·인증 정보가 포함될 수 있어 암호화된 개인 저장소가 필수. 압축 파일 또는 임시 폴더를 GitHub·채팅·공개 링크에 업로드하지 않는다. 고객이 관리하는 강한 복원 암호를 사용하고 서버가 파괴될 때에도 찾을 수 있도록 별도 안전한 방법으로 보관한다. 암호를 스크립트 파일·CLI 명령행·환경변수·원격 로그에 노출시키지 않는다. 구현 가능한 검증된 암호화 도구/복구 경로를 선정한 뒤 실제 데이터에 적용한다.
2. **실행 중 서버 정합성:** Paper가 실행 중인 세계 디렉터리를 단순 `Copy-Item`/OneDrive 실시간 동기화/DriveFS 동기화로 바로 백업하지 않는다. GSC `withOnlineWorldFreeze`의 기존 방식은 `save-off`→`save-all flush`→아카이브→`save-on`을 사용하지만, *느린 클라우드 업로드 전체 시간* 동안 save-off를 유지하면 안 된다. 전체 월드 백업은 안전한 짧은 일관성 있는 로컬/볼륨 스냅샷 또는 승인된 일시 정지 후 스냅샷을 먼저 만든 후 비동기 업로드한다. VSS 등 COW 스냅샷은 별도 공간·관리자 요건이 있으므로 무검증 즉시 적용하지 않는다.
3. **백업 저장 흐름:** 민감 콘텐츠를 임시 평문으로 저장하지 않는 방식 선택 → 개인/암호화된 Google Drive 목적지에 스냅샷 아카이브 적재 → 각 파일과 패키지 SHA-256 및 크기·원본 스냅샷 식별자 확인 → OneDrive 목적지에 P0 및 저장공간이 허용되는 P1 이중 보관 → 공급자 측 동기화 완료와 실제 웹/독립 기기 다운로드 검증. 가능하면 재시도 안전한 **새 파일명/부분 파일명**으로 작성하고 기존 검증된 백업은 덮어쓰지 않는다.
4. **낮은 로컬 용량:** 작업 전 실제 원본 바이트와 Windows 볼륨 여유공간·DriveFS 캐시 사용량·OneDrive 사용량·각 클라우드 잔여 저장공간의 범위를 반드시 확인. DriveFS 스트리밍/OneDrive 온디맨드라고 로컬 임시 사용량 `0`을 가정하지 않는다. 현재 런타임/업데이트의 디스크 사용량이 급증할 수 있으므로 공간 부족이면 fail-closed.
5. **손상 없는 실패/재시도:** 업로드 실패·네트워크 끊김·SHA mismatch 발생 시 사용 중인 서버/월드/원본·기존 정상 백업을 건드리지 않는다. 새 복구본을 **verified=false**로 표시하고, 미완료 파일은 사용 금지. 임시 파일 자동 영구삭제는 하지 않으며, 사용자 확인 후만 정리.
6. **검증:** 다운로드하여 해시를 다시 비교하고, 별도 일회용 테스트 위치에서 ZIP/암호 해제와 실제 GSC/Paper/Java 복원을 **원본 덮어쓰기 없이** 검증. 구독 서비스 웹에서 파일이 보인다는 사실만으로 전체 복구 PASS 선언 금지.

## 4. 최종 Stable 단계와 연결

- **12.7** GSC Host 4.5.1, Playground ONLINE 0명/0작업은 사전검사에서 확인. 당시 `AUTOMATIC_UPDATE_POLICY_MUST_BE_REVIEWED` + `TARGET_PROTECTED_VERIFIED_FULL_BACKUP_NOT_CONFIRMED` 때문에 실서버 오프라인 기동 미실행. 실제 백업 삭제 사실과 합치. 2026-10-13 이전의 Golden 4/4 및 캐시 84/84 기록은 유지.
- **12.11** 공개된 GSC 4.5.1 **서명 Beta**는 파일 SHA·Ed25519 서명과 변조 거부 CI PASS. 실서버 Canary 적용·롤백은 복구 자산 검증 전 미실행. 과거 4.3.9 RC1을 4.5.1 호스트에 다운그레이드하지 않음.
- **12.5** 별도 표준 사용자 계정 부재, Users 상속 WRITE ACE 실효 권한 미검증·방화벽 광범위 Allow 후보 검토 필요. 실제 ACL/방화벽 변경 전 rollback 경로 요구.
- **12.10** ONLINE Paper 세 인스턴스 Java/RCON Native IPv4 6/6·동일 소유 PID/루프백 실제 스코프 PASS, 전체 WFP/effective policy는 별도.
- **12.12** 실제 8시간·97샘플 실서버 TCP/프로세스 안정성 범위 PASS. 같은 8시간 재시행 없음.
- **12.13** 기존 수동 GSC 4.5.1/GSCM 1.5.1 Stable은 공개 유지. PR #53은 Draft·미병합, `FINAL-RELEASE-GATES.json`의 strict `stable_release_allowed=false` 유지. Cloud preflight CI만으로 12.7·12.11·12.5 또는 최종 서명 Stable을 PASS 처리하지 않음.

**사용자가 해야 할 최초 실기기 작업:** Cloud READ-ONLY ZIP을 서버 PC에서 한 번 실행하고, **`DAY12-CLOUD-PREFLIGHT-SHARE-ONLY-THIS.json`만 공유**. 그 결과로 *안전하고 용량에 맞는* 실제 백업 절차를 확정한다. 선택한 동기화 폴더 또는 서버 경로 원문은 채팅에 올릴 필요가 없다.
