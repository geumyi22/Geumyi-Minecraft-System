금이 Minecraft System / Day12 실제 비관리자 계정 접근 권한 검사 (읽기 전용)

목표
- 관리자 권한이 없는 '실제 Windows 표준 사용자 계정'으로, GSC 설치 루트의
  파일 생성 권한(FILE_ADD_FILE) 및 하위 폴더 생성 권한(FILE_ADD_SUBDIRECTORY)을
  요청만 하여 Windows 커널 접근 제어의 성공/거절을 확인합니다.
- CreateFileW(OPEN_EXISTING + FILE_FLAG_BACKUP_SEMANTICS)만 사용하여 기존 루트
  디렉터리 핸들을 열었다 닫습니다. 실제 파일/폴더를 생성하지 않습니다.
- 설치 파일, 서비스, 방화벽, 월드, 백업 및 Windows ACL을 수정하지 않습니다.
- TEST는 관리자 계정, UAC 제한 토큰, SYSTEM/서비스 계정을 표준 사용자라고 주장하지 않습니다.
  해당 토큰이면 BLOCKED_UNVERIFIED가 정상입니다.

필수 조건
- Windows에 원래 존재하던 실제 표준 사용자 계정으로 로그인해야 합니다.
- 관리자로 실행하면 안 됩니다.
- 계정이 없다면 임의로 계정을 만들거나 권한을 바꾸지 마세요. ChatGPT에 문의하세요.
- 소스 ZIP 파일을 모두 같은 폴더에 압축 해제합니다.

실행
1. 실제 GSC 서버 PC에서 표준 사용자 계정으로 로그인합니다.
2. START_Day12_Phase5_GSC_StandardUser_NoWriteProbe_READ_ONLY.cmd 실행.
3. 생성된 DAY12-GSC-STANDARD-USER-NOWRITE-SHARE-ONLY-THIS-*.json만 전송.
4. BLOCKED면 생성된 JSON이나 오류 화면만 전달하고, 강제로 계속하지 않습니다.

판독
- ALLOWED: 해당 표준 사용자 토큰으로 대상 디렉터리 생성 권한을 가진 핸들을 얻음.
  실제 파일 생성은 하지 않았으나 중요한 보안 위험을 확인한 것입니다.
- DENIED: 그 토큰에 대해 해당 생성 권한의 핸들이 거부됨.
  이것만으로 모든 표준 사용자, 자식 디렉터리, 다른 파일 작업을 검증했다고 볼 수 없습니다.
- UNVERIFIED: 토큰/경로/운영체제 검사 실패. 성공·차단 증거가 아닙니다.
- strict_security_gate는 항상 NOT_PASSED입니다. 실환경 ACL 수정이나 배포를 승인하지 않습니다.
- 공유용 JSON에는 계정, 파일명, SID, 실제 경로, DACL/SDDL, 토큰이 포함되지 않습니다.
