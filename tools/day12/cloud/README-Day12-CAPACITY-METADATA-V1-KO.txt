금이 서버 Day12 복구 용량 조사 v1 (READ ONLY / CI 검증 후에만 사용)

용도: 기존 v5 클라우드 경로 검사 결과를 교체하거나 다시 실행하지 않고,
실제 Windows 서버 PC에서 서버 원본 4개 + GSC 상태의 크기 단서를
읽기 전용으로 수집합니다. 클라우드 원격 잔여 용량은 수집할 수 없습니다.

실행 조건:
- GitHub PR #53의 'Day12 Recovery Capacity Metadata v1' CI SUCCESS 확인.
- 기존 월드 백업이 삭제된 상황을 전제로 합니다. 검사 자체는 백업이 아닙니다.
- 이 폴더에 v4/v5 .ps1, 새 capacity .ps1, CMD 파일을 함께 둡니다.
- 서버 PC에서 RUN_Day12_Recovery_Capacity_Metadata_READ_ONLY.cmd 실행.
- 자동 실행, 관리자 권한 상승, 서버 종료/재시작, 백업/압축/업로드 없음.
- 결과에 표시된 SHARE-ONLY-THIS.json 파일만 채팅으로 보냅니다.
- 8시간 soak, Native 6/6 검사, v3/v4/v5 경로 검사는 재실행하지 않습니다.

검사 범위/한계:
- Get-ChildItem/FileInfo.Length로 파일 메타데이터만 열거합니다. 파일 내용은
  열거나 복사하지 않지만, OneDrive 가상 폴더 열거 과정에서 클라우드
  클라이언트와 OS가 메타데이터 동기화를 수행할 가능성까지 배제하지 않습니다.
- 내부 재분석지점(reparse), Offline/recall 속성 파일·폴더는
  들어가지 않고 제외 수량만 표시합니다. 크기가 빠질 수 있습니다.
- 각 폴더별 25,000 항목 또는 45초 제한. 실패/중복 경로는
  INCOMPLETE로 표시합니다. 논리적 바이트 수는 스냅샷이나
  정확한 클라우드 사용량/온디스크 사용량을 뜻하지 않습니다.
- 윈도우 LOCALAPPDATA 쪽 로컬 드라이브 여유 공간만 표시하며
  Google Drive G: 가상 드라이브 여유 공간을 원격 quota로 취급하지 않습니다.
- Google Drive / OneDrive 실제 원격 quota는 각 계정의 관리 화면 또는
  승인된 제공자 API에서 별도 확인할 필요가 있습니다.
- 절대 경로, 사용자 이름, RCON 암호, 키, 장치 토큰, 파일명은
  공유 결과에 기록하지 않습니다. 디스크 파일을 검사하여 해시하지 않습니다.
- 보고서 JSON만 LOCALAPPDATA 아래 분리된 신규 진단 폴더에 만듭니다.
- 생산 백업/복원·ACL/방화벽·월드/서버 변경은 금지.
- 보고서의 stable_release_allowed=false는 변경하지 않습니다.

검사에서 BLOCKED가 발생하면 반복 실행하지 말고 메시지와 원인을 공유하세요.
