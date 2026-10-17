금이 서버 Day12 P0 Google Drive 복구본 전송 — 읽기 전용 사전검사

이 검사는 Google Drive에 파일을 복사하지 않습니다.
기존 로컬 암호화 폴더의 파일 이름/크기/속성만 조회합니다.
일반 서버 원본(OneDrive), 백업 비밀번호, 암호문 본문은 읽지 않습니다.
Google Drive의 G: 루트가 접근 가능한지만 확인하고 자식은 열거하지 않습니다.

실행: RUN_Day12_P0_Google_Transfer_Preflight_READ_ONLY.cmd
공유: 출력된 상태 텍스트만. 사용자 계정/암호/키/설정/암호문은 공유하지 마세요.

검사 기준: P0 암호화 part-000..019.gcm, header.json, manifest.gcm,
LOCAL_CAPTURE_VERIFIED.txt, 정확히 23개 항목의 기본 메타데이터.
PRELIGHT_REVIEW_READY는 업로드 허가나 복구 성공을 의미하지 않습니다.

유의: G: 마운트 확인은 Google 웹 서버 측 사본 존재나 2TB 계정 정체성
독립 검증이 아닙니다. 업로드 성공 여부와 독립 다운로드/복호화는
반드시 다른 단계에서 확인해야 합니다.
이 검사로 Other Paper 기동, 서버/GSC 재시작, 동기화 설정 변경,
원본 OneDrive 접근 또는 Google Drive 쓰기는 전혀 하지 않습니다.
실제 G: 암호문 전송은 별도 운영자 승인 이후에만 진행합니다.
