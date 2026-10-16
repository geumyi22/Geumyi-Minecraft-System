금이 서버 Day12 P0 로컬 암호화 설정 복구본 - 운영자 실행 도구
============================================================

상태: 합성 Windows/Linux 테스트 성공 후에만 사용할 수 있는 운영자 도구.
GitHub의 source나 다운로드 ZIP이 CI 성공을 대체하지 않습니다.

중요: 이 ZIP은 게임 전체 월드 백업 도구가 아닙니다.
선별 파일 20개만 읽는 "P0 핵심 설정/키" 로컬 암호화 백업입니다.
다음 파일만 암호화 대상으로 합니다.
- GSC Host server.json 1개
- Wild/Playground/Other/Lobby server.properties 총 4개
- 세 Velocity proxy의 velocity.toml/forwarding.secret,
  Geyser-Velocity config.yml, floodgate config.yml, floodgate key.pem
  각 5개씩 총 15개.
합계 20개. 이 파일들의 등록 루트는 기존 v4/v5 GSC+API
일치 검사와 Day10 프록시 예약작업 루트로 다시 확인합니다.
Paper 파일은 OneDrive placeholder를 다운로드할 수 있습니다.
이 제한된 파일 읽기를 사용자 승인했으나,
OneDrive/Google Drive 동기화 정책은 변경하지 않습니다.

압축 풀고, 서버 PC에서 일반 권한으로
RUN_Day12_P0_Local_Encrypted_Capture.cmd 실행.
- 정확히 SOURCE_SELECTED_CONSENT를 입력해야 실제 백업 파일 읽기를 시작합니다.
- 복구 암호는 20자 이상 256자 이하를 두 번, 화면에 표시하지 않고 입력합니다.
- 복구 암호는 GitHub, 채팅, 메일, Google Drive 평문 메모, 사진 등에 저장하지 마세요.
- 복구 암호를 잃으면 이 백업을 복원하지 못할 수 있습니다.
  오프라인으로 안전하게 별도 보관하고 복구용 별도 기기에서
  암호를 다시 입력해 복호화할 수 있는지 향후 검증해야 합니다.
- 현재 백업 암호 KDF는 PBKDF2-HMAC-SHA256 450,000회, 랜덤 salt 24바이트,
  임의 archive ID, 각각 별도 nonce인 AES-256-GCM 입니다.
- 출력은 LOCALAPPDATA의 Geumyi-P0-Encrypted-Staging/P0-... 하위의
  새 로컬 폴더에만 생성. source/config 전체 경로는 전송되지 않습니다.
- 새 출력 폴더가 이미 있으면 즉시 실패하며 덮어쓰지 않습니다.
- 최대 개별 8MiB, 총 48MiB. 더 크거나 파일이 중간에 바뀌면
  FAIL CLOSED; 남은 부분 암호문은 INCOMPLETE이며 업로드하지 마세요.
- 성공해도 현재 온라인인 GSC/프록시/플러그인 별도 상태와
  설정 간 시점 일치는 증명되지 않습니다.
- 서버 시작/종료/월드 저장 조작, Other Paper 기동 없음.
- 기존 OneDrive 소스 파일을 지우거나 고치지 않음.
- 20개 설정 파일 이외에는 고정 경로에서도 읽지 않음.
  다만 경로 검증을 위해 GSC 설정 및 경로 포인터를 로컬 메모리에서 읽고,
  설정/API endpoint http://127.0.0.1:8790 를 조회합니다.
- Google Drive로 업로드하거나 클라우드에서 재다운로드하지 않습니다.
  복원 실행파일과 독립 복원 테스트는 별도 후속 단계입니다.
- Google Drive G:에 평문 원본을 복사하지 마세요.
- 프로그램이 오류를 출력하면 다시 실행하지 말고 'P0_GATE_...'
  또는 'P0_CAPTURE_BLOCKED...' 코드만 공유해 주세요.
  부분 생성된 로컬 파일은 자동 삭제하지 않습니다.
- 결과를 보내실 때 개인 경로/암호키/설정 파일/암호문 원본은 절대 전송하지 마세요.

PR #53 Draft; P0 백업 전체 및 안정 버전 배포 승인 미완료.
