금이 서버 Day12 P0 복구 준비 — 중요 설정 파일 존재 여부만 확인 (READ ONLY)

실행: CI 검증된 ZIP을 서버 PC에 압축 해제 후
RUN_Day12_P0_Config_Presence_READ_ONLY.cmd 더블클릭.
일반 권한으로 실행. 결과의 DAY12-P0-PRESENCE-V1-SHARE-ONLY-THIS.json 만 공유.
개별 설정 파일, API 토큰, 비밀번호, 보안키, 경로는 공유하지 마세요.

주의:
- 이 도구는 백업을 만들지 않고 P0 후보 파일 내용도 읽지 않습니다.
- 단, 실제 서버 경로를 확인하기 위해 기존 v4/v5 resolver가
  GSC server.json 및 경로 포인터의 텍스트를 로컬 메모리에서 읽습니다.
  채팅/로그/JSON에 내용이나 경로를 기록하지 않습니다.
- GSC server.json 및 네 Paper 서버의 알려진 설정 파일 1개씩을 비롯한
  한정된 정확한 파일 이름만 조회합니다. 월드/플러그인 전체 목록을
  열거하지 않습니다.
- OneDrive 파일은 Files On-Demand 재분석/오프라인 표식이 있을 수
  있으므로, 그 파일의 존재 정보만 확인하고 내용·크기를 읽지 않습니다.
- OS/동기화 클라이언트가 메타데이터 요청 자체에 반응할 가능성은
  배제할 수 없습니다. 다운로드, 속성 고정/해제, 강제 동기화는 하지 마세요.
- 세 Velocity 실제 실행 폴더의 경로, forwarding.secret, Geyser/Floodgate
  설정·키, RCON/StatusAgent 상태는 별도 확인이 필요합니다.
- 다른 서버(Other)는 OFFLINE 상태 그대로 유지합니다.
- 파일 하나가 관측되더라도 시점 일치/복구 가능성이 증명된 것은 아닙니다.
- config 파일의 자체 암호화가 완료되기 전 Google Drive G: 또는 OneDrive
  어디에도 평문 설정과 비밀키 복사 금지.
- 개인 폴더 경로와 시크릿은 결과 JSON에 포함하지 않습니다.
- 오류/차단 시 반복하지 말고 화면만 공유하세요.
- 이 검사로 P0 백업, 클라우드 업로드, 복원 또는 최종 Stable을 PASS로
  처리할 수 없습니다.
