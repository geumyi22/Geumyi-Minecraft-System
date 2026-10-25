Geumyi Minecraft System / Day12.12 8시간 연속 안정성 검사 (READ ONLY)

[무엇을 확인하나요?]
- 실제 서버 PC의 GSC Host 서비스와 로컬 TCP **25565/25566/8787**을 필수 검사합니다.
- 2026-10-13 운영자 확인: 기타(Other) Paper 서버는 의도적으로 OFFLINE입니다. 본 실행용 CMD는 이 기대 상태를 **명시적으로** 지정합니다.
- Velocity 25567은 기타 Paper의 상태와 무관하게 열려 있을 수 있는 **프록시 프런트엔드**입니다. 이 포트는 기록만 하며 기타 Paper 서버가 OFFLINE이라는 이유만으로 실패 처리하지 않습니다.
- 8시간 동안 5분 간격으로 Windows Java/GSC 프로세스의 이름, PID, 시작 시각, 메모리, 핸들, CPU를 관찰합니다.
- 기동 중단, 프로세스 재시작, 샘플 간격 누락, 관찰 실패와 TCP 도달성 이상을 요약합니다.
- 검사 도중 서버를 시작/중지/재시작하거나 파일, 월드, 백업, 방화벽, ACL을 변경하지 않습니다.

[왜 GSC API GET을 쓰지 않나요?]
- 최신 인증 보호 설정에서는 인증 없는 API GET이 401을 반환할 수 있습니다.
- 401은 게임 서버 오류라는 뜻이 아니므로, 인증 자격증명을 요구하지 않는 로컬 TCP 연결 확인을 사용합니다.
- 이것은 Velocity/GSC Host TCP 도달성만 확인하며 **기타 Paper의 실제 ONLINE/OFFLINE 상태, Bedrock RakNet, 실제 게임 플레이, GSC 인증 기능, OS 소켓 소유권, 보안 정책을 증명하지 않습니다.**
- 다른 때 기타를 켤 계획이면 이 ZIP을 그대로 실행하지 말고 검사 기대 상태를 먼저 조정해 주세요. 임의로 서버를 시작하지 마세요.

[실행]
1. 실제 마인크래프트 서버 Windows PC에서 ZIP 내부 파일 3개를 같은 폴더에 압축 해제합니다.
2. 기타 Paper가 현재 의도적으로 OFFLINE인 상태에서 8시간 동안 서버가 유지될 때 Start_Day12_8H_Soak_READ_ONLY.cmd를 실행합니다. 이 CMD는 `-ExpectedOtherBackendState OFFLINE`을 명시적으로 전달합니다.
3. 창을 닫거나 절전/로그아웃/재부팅하지 마세요. 8시간 종료 후 결과 폴더 경로가 화면에 나옵니다.
4. 바탕화면 Geumyi-Day12-Soak-YYYYMMDD-HHmmss 폴더 안
   DAY12-SOAK-SUMMARY-SHARE-ONLY-THIS.json 하나만 ChatGPT에 첨부하세요.
5. PRIVATE-SAMPLES-DO-NOT-UPLOAD.ndjson에는 프로세스 PID 및 시각 등이 들어 있으므로 업로드하지 마세요.

[BLOCKED]
- 테스트는 시작 전 로컬 TCP와 GSC 서비스 존재 여부를 검사합니다.
- 사전 검사를 통과하지 못한 경우 8시간 검사를 시작하지 않습니다. OFFLINE 기타 서버의 프록시 25567 상태는 이 판정을 결정하지 않습니다. 서버나 방화벽 설정을 임의 변경하지 말고 화면만 보내세요.
- 검사 중 창이 닫히거나 오류가 발생하면 8시간 PASS로 처리하지 않습니다. 기존 출력은 보존하세요.

[중요한 판정 범위]
- 스크립트 결과는 항상 REVIEW_REQUIRED입니다. 8시간이 지났다는 사실만으로 Stable을 자동 승인하지 않습니다.
- 관측 가능한 필수 TCP·프로세스 연속성, 로그 분석 및 나머지 보안/Canary/오프라인 복구 검증을 함께 평가해야 합니다. 요약 JSON의 other_backend_expected_state_by_operator는 운영자 기대값이며 실제 검증된 서버 상태가 아닙니다.
- Windows 사용자 계정을 새로 만들 필요가 없습니다.
