금이 마인크래프트 서버 Day12.5 - 명시적 ACL / 상속 차단 객체 읽기 전용 재검사

목적
- 앞서 조회한 GSC 하위 14,302개 항목 중 별도 ACL이 설정된 6개 객체의 종류 및 권한 위험 가능성을 숫자만으로 확인합니다.
- 실제 폴더명/파일명/경로, SID, 사용자 이름, 원문 ACL(SDDL), 토큰, 월드 및 백업 내용은 수집 결과 JSON에 포함하지 않습니다.
- BUILTIN\Users, Everyone, Authenticated Users, Guests 같은 넓은 권한 주체에 대한 명시적 또는 상속된 쓰기 허용 ACE의 '존재 여부'만 분류합니다.
- ACE 존재 여부만으로 실제 Windows 표준 사용자의 유효 접근 권한(Effective Access)을 증명하지는 못합니다.

실행 방법
1. 실제 GSC를 실행하는 서버 PC에서 ZIP 전체를 압축 해제합니다.
2. CMD와 PS1 파일을 같은 폴더에 둡니다.
3. START_Day12_Phase5_GSC_ExplicitAcl_Review_READ_ONLY.cmd를 실행합니다.
4. 새로 생성된 DAY12-GSC-EXPLICIT-ACL-SHARE-ONLY-THIS-*.json 한 개만 ChatGPT로 보냅니다.
5. 오류나 BLOCKED 표시가 나오면 ACL을 변경하지 말고 화면을 보내주세요.

중요
- 실제 서버의 ACL 변경, 서버 중지/재시작, 월드 변경, 백업/복구/삭제, 방화벽 변경은 하지 않습니다.
- 프로그램 자체 테스트는 계산만 수행합니다. 검사 시에도 파일 내용을 열거나 심볼릭 링크·정션을 따라가지 않습니다.
- 검사 결과 JSON은 LOCALAPPDATA에 생성됩니다. 이 JSON 외의 파일, 특히 보호된 서비스 설정이나 개인 ACL 증거 파일은 업로드하지 마세요.
- strict_security_gate는 항상 NOT_PASSED입니다. 이번 단계만으로 운영 ACL 변경을 승인할 수 없습니다.
