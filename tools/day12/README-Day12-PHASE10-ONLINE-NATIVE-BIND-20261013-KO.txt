Day 12.10 / 현재 ONLINE 백엔드 Java + RCON 바인딩·프로세스 소유권 검사

진행 전 조건
- 기타(Other) Paper 서버는 현재 운영자 의도로 OFFLINE. 절대로 검사 때문에 켜지 마세요.
- 서버 PC에서 GSC Host 서비스가 원래 정상 동작 중일 때만 실행하세요.
- 기존 정상 구동 중인 Wild/Playground/Lobby 각각의 Java·RCON 포트 6개를 대상 범위로 삼습니다.
- 별도 Windows 표준 사용자 계정을 만들 필요가 없습니다.
- 프로그램이 가동 중인지, 플레이어가 있는지 무관하게 검사 자체는 조회만 합니다.
  실제 서버 재시작, 트랜잭션, 성능 부하·서명 설치·방화벽·ACL 변경을 하지 않습니다.

한 번 실행
1. ZIP을 다운로드해 모든 파일을 같은 폴더에 압축 해제하세요.
2. 서버 PC에서 RUN_Day12_Phase10_Current_Online_Bind_READ_ONLY.cmd를 **한 번만** 실행.
3. 실행 자체는 관리자 권한 상승을 요청하지 않습니다. Windows 프로세스 정보 접근이 거부되면 BLOCKED로 끝날 수 있습니다.
4. 바탕화면 Geumyi-Day12-Native-Scope-* 아래 DAY12-NATIVE-BIND-SHARE-ONLY-THIS.json만 공유.
5. 실행 중 오류가 뜨고 JSON이 생성되지 않으면 그 화면만 보내세요. 반복 실행하지 마세요.

검사하는 내용
- Windows iphlpapi GetExtendedTcpTable의 BASIC_LISTENER IPv4, OWNER_PID_LISTENER IPv4 및 IPv6.
- Windows 26220의 상태값 0 예외에서도 **리스너 전용 API 테이블**임을 인정하되, 모든 테이블의 state 0을 임의로 LISTEN 인정하지는 않습니다.
- 임시 127.0.0.1 포트 0 자동 할당 테스트로 자기 프로세스의 listener PID를 실제로 찾는지 긍정 대조.
- Wild: 25570/25575, Playground: 25571/25576, Lobby: 25573/25579.
- RCON과 Java 포트가 같은 Paper JVM 소유인지, 명령행의 paper*.jar를 읽어 식별 가능한지(실제 명령행은 보고서에 포함하지 않음).
- 원격 노출이 위험한 0.0.0.0, :: 또는 다른 비루프백 IPv4/IPv6 바인딩의 관측 여부.
- Other: Java 25572/RCON 25577이 **예상 밖으로 열려 있으면** BLOCKED. 이것은 검사에서 Other를 시작하지 않았음을 의미.
- 보고서는 포트별 명령행, IP, PID, 실제 파일 경로, 사용자 이름, 토큰을 저장하지 않습니다.

판정 범위
- SCOPED_NATIVE_BIND_OWNER_REVIEW_REQUIRED면 해당 순간의 온라인 6개 Java/RCON Native OWNER_PID/loopback/Paper 역할 매칭을 확인한 것입니다.
- BLOCKED_REVIEW_REQUIRED이면 부분적 불일치 또는 자료 부족. 즉각적인 침해를 의미하지 않습니다.
- 어떤 결과도 방화벽 WFP 전체, 네트워크의 모든 경로, GSC 유효 ACL, 게임 Bedrock 접속, 수동 Stable 설치, 정식 릴리즈 12.13을 승인하지 않습니다.
- 기존 v3.1 실제 서버 6/6 자료와 0/8 LAN·Tailscale 자료는 보존·함께 검토합니다.
- 같은 방식의 진단이 재차 BLOCKED되면 추가 반복 대신 다른 근거로 판단합니다.
- 실기기 검사 전까지 GitHub Windows CI PASS는 서버 PC 실효 보안을 뜻하지 않습니다.
