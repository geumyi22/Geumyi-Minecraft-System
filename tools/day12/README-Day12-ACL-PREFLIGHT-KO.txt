금이 Day 12.5 ACL 변경 전 사전점검 (READ ONLY)

목적: GSC 폴더의 정확한 권한 상속/소유자와 GSC Host 서비스 계정 유형을
읽기 전용으로 확인해, 이후 별도 승인받을 ACL 최소 권한 변경 범위를 좁힙니다.

실행 대상: 실제 마인크래프트 Windows 서버 PC.
1. GitHub Actions의 Day 12 Read-Only Safety CI가 SUCCESS인지 확인.
2. day12-acl-predeployment-readonly-kit 아티팩트 ZIP 다운로드 후 압축 해제.
3. START_Day12_Phase5_ACL_Change_Preflight_READ_ONLY.cmd를 일반 실행.
4. [1/2] 자체검사와 [2/2] 읽기 전용 검사 통과 후 열리는 결과 폴더에서
   가장 최근 하위 폴더의 DAY12-ACL-CHANGE-PREFLIGHT-SHARE-ONLY-THIS.json
   파일 하나만 ChatGPT에 보내세요.

보내면 안 되는 파일:
PRIVATE-ACL-SDDL-SNAPSHOT-DO-NOT-SHARE.json
이 파일에는 원본 ACL/소유자/실제 로컬 경로가 포함됩니다.
서버 PC의 %LOCALAPPDATA%\Geumyi-Day12-ACL-Preflight 에 그대로 보관하세요.

절대 실행하지 않는 작업:
- 기존 GSC 폴더/파일 ACL 변경
- 방화벽 변경, 서비스 재시작, 서버 종료
- 서버 월드/백업/설정 변경
- GSC 업데이트 적용, GitHub 릴리즈 승격

주의:
도구는 조사 기록을 사용자 프로필 LOCALAPPDATA 아래 새 폴더에 만듭니다.
해당 새 결과 폴더만 접근 제한 ACL로 보호합니다. 운영 GSC ACL에는
Set-Acl/icacls 변경을 하지 않습니다.
자체검사가 실패하면 그대로 중단하고 화면을 보내 주세요.
검사 성공도 보안 게이트 최종 PASS나 ACL 수정 승인을 뜻하지 않습니다.
