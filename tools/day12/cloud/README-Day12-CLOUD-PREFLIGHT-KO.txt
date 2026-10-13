금이 마인크래프트 Day12 — Windows 경로 진단 v4 (2026-10-14)

v3를 다시 실행하지 않습니다. 새 v4 ZIP 전체를 압축 해제한 뒤
RUN_Day12_Cloud_Recovery_Preflight_READ_ONLY.cmd를 서버 PC에서 한 번 실행하세요.

1. Google Drive의 기존 '내 드라이브' 폴더를 선택합니다. G: 가상 드라이브도 지원합니다.
2. OneDrive 환경변수·Windows 알려진 폴더·계정/동기화 루트 레지스트리·Explorer
   셸 항목에서 발견한 기존 폴더를 PC 화면에서만 보여 줍니다. 의도한 폴더의 번호를
   입력하여 확인하거나 Enter를 눌러 폴더를 선택합니다. 계정 소유권/동기화 검증은 아닙니다.
3. 완료하면 결과 폴더가 열립니다. 다음 JSON 하나만 채팅에 첨부하세요.
   DAY12-CLOUD-PREFLIGHT-V4-SHARE-ONLY-THIS.json
   결과는 동기화될 수 있는 바탕화면 대신 LOCALAPPDATA\Geumyi-ReadOnly-Diagnostics에 저장합니다.

공유 JSON에는 사용자 이름, 서버/클라우드 경로, 계정명, 토큰, 원본 API/설정을 넣지 않습니다.
경로 원문은 OneDrive 선택 시 PC 화면에서만 표시합니다. 화면이나 server.json은 보내지 마세요.
동봉 BUILD-INFO-V4.json은 CI가 확인한 소스 커밋과 파일 해시이며 실행 결과가 아닙니다.

진단은 GSC server.json과 localhost:8790의 GET /api/settings를 읽습니다.
소스상 API는 {servers:[{id,path,path_file,...}]}입니다. path와 path_file은 servers[] 안에 있습니다.
직접 path가 있으면 우선하며 path_file로 덮어쓰지 않습니다. UTF-8 BOM, 따옴표,
%환경변수%, $환경변수/${환경변수}를 처리합니다. 상대 경로는 Host 작업 폴더를
추측하지 않고 RELATIVE_HOST_CONTEXT_REQUIRED로 남깁니다. 설정 접근 실패여도 API를 확인합니다.
API의 data/settings/config 래퍼는 제한적인 호환 처리이며 실제 Host 소스 계약과 구분합니다.
여러 목록, 중복 ID, 서로 다른 접근 가능한 설정/API 경로는 모호한 결과로 차단합니다.
401/403은 인증 거부로 기록하며 인증을 우회하지 않습니다. HTTP 리디렉션은 따르지 않습니다.

폴더/reparse/junction의 정확한 경로 메타데이터와 server.properties 존재 메타데이터만 확인합니다.
월드/서버 폴더 재귀 탐색, 크기 산정, 파일 복사, 백업, 업로드, 복원, 서버 정지/업데이트는 하지 않습니다.
임시 합성 테스트 파일과 공유용 결과 JSON만 새로 만듭니다. 테스트는 전용 임시 폴더를 사용합니다.
경로 접근 실패나 루트 0/3은 데이터 손실·월드 삭제·서버 중단을 뜻하지 않습니다.
reparse 최종 대상과 물리적 경로 중복은 미검증이므로 향후 백업 전에 별도 확인이 필요합니다.

Google Drive G:의 Explorer 표시 930GB/여유 410GB는 Windows 가상 볼륨/캐시 표시일 수 있습니다.
Google 2TB 클라우드 쿼터나 실제 잔여 용량과 혼동하지 않습니다. 로컬 캐시 용량도 미검증입니다.
Windows가 FAT32라고 보고하면 실제 파일시스템 여부와 파일 제한 확인 필요로 기록합니다.
실제 FAT32는 파일 하나가 4GiB 이상일 수 없습니다(최대 4,294,967,295바이트).
DriveFS의 에뮬레이션된 FAT32 표시만으로 이 제한의 실제 적용 여부를 확정하지 않습니다.
이 진단은 확인용 대용량 파일을 만들거나 업로드하지 않습니다.

기타 Other는 의도한 OFFLINE 상태입니다. 실제 프로세스 상태는 이 진단으로 증명하지 않습니다.
이전에 삭제된 백업이 복구되었다고 취급하지 않습니다. 백업·업로드·복원 증거는 여전히 없으며
PR #53은 Draft, 최종 Stable/운영 변경 게이트는 BLOCKED입니다.
CI PASS는 합성 Windows 테스트가 통과했다는 뜻이며 실제 서버 경로·클라우드 검증 PASS가 아닙니다.
