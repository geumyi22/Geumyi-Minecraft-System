금이 서버 Day12 — Google Drive로 P0 암호문만 안전하게 복사 (v1)
===============================================================

대상: 이미 독립 복호화 검증 PASS한 기존 로컬 P0 암호화 아카이브.
데이터: part-000.gcm ~ part-019.gcm 20개와
header.json, manifest.gcm, LOCAL_CAPTURE_VERIFIED.txt 3개 (정확히 23개).
운영자 확인 기존 원본 합계: 81,413바이트. 다르면 차단.

1. 서버 PC에서 압축 해제. 가급적 OneDrive/Google Drive 외 로컬 폴더.
2. 실행: RUN_Day12_P0_Google_Encrypted_Copy.cmd
3. 탐색기에서 본인 Google Drive 2TB 계정의 G:를 열고
   'My Drive' 또는 '내 드라이브' 폴더가 맞는지 확인.
4. 해당 폴더의 전체 경로를 복사해 CMD 질문에 붙여 넣기.
   직접 선택 가능한 허용 위치: G:\My Drive 또는 G:\내 드라이브.
   G: 루트 / 공유 드라이브 / OneDrive / 임의의 하위폴더는 차단.
5. GOOGLE_P0_ENCRYPTED_UPLOAD_APPROVED 를 입력하면
   기존 로컬 암호화 23개 파일을 새 Google 전용 폴더에 복사.
6. 결과의 P0_ 상태 줄과 P0_G_MOUNT_NEW_FOLDER_NAME만 공유.

중요: 복구 암호, 서비스 토큰, 원본 설정 파일, 암호문 파일을
ChatGPT/GitHub로 보내지 마세요. 이 복사는 복구 암호를 사용하지 않음.
비밀키는 기존 로컬 아카이브와 별도로 오프라인 보관.

안전장치:
- 서버 Paper/GSC/Velocity 원본과 OneDrive 설정 경로에 접근하지 않음.
- 기존 암호화 폴더의 파일을 읽기만 하고 수정/삭제하지 않음.
- 목적지는 기존 파일을 건드리지 않는 완전히 새 고유 폴더.
- 암호문만 복사하며 파일마다 복사 전/후 SHA-256 일치 검증.
- 누락/추가 파일, 암호문 변경, 다른 용량, 기존 목적지면 차단.
- 오류 시 Google 목적지에 부분 파일이 남을 수 있음.
  그 부분 폴더를 완전한 백업으로 취급하지 말 것; 임의 삭제도 금지.
- Google Drive for desktop 동기화가 느리거나 실패할 수 있음.
  G: 복사 SHA256 PASS는 Google 웹 원격 저장 완료를 의미하지 않음.
  이후 Google 웹에서 새 폴더를 확인하고 별도 내려받아
  AES-GCM 검증해야 독립 클라우드 복구 증명 가능.
- 복사 성공해도 월드/플러그인 P1, 서버 재시작 복원, Stable은 미완료.

문제 발생 시 P0_GOOGLE_COPY_ 오류 코드만 보내주세요.
기존 로컬 백업, OneDrive 서버 원본, Other Paper OFFLINE 유지.
