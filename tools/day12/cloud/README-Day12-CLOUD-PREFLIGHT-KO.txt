금이 마인크래프트 Day12 — Google Drive 2TB + Microsoft OneDrive 1TB 복구 준비
2026-10-14 · 원본 서버 변경 없음 · **읽기 전용 1단계**

사용자 확인된 사실: 두 클라우드에 로그인되어 있으며 서버 PC에서 업로드 가능.
단, 실제 남은 용량, Windows 동기화 위치, 현재 계정, 업로드 완료 및 복원 가능 여부는 아직 미검증.
이 검사기는 월드/설정/백업을 건드리지 않으며, 파일을 업로드하지도 않습니다.

[준비]
- 실제 Windows 마인크래프트 서버 PC에서 실행하세요.
- Google Drive 데스크톱 앱과 OneDrive가 로그인·실행되어 있어야 합니다.
- 서버와 기타(Other)는 현재 설정 그대로 두세요. 기타 서버는 계속 OFFLINE입니다.
- 과거 서버 백업이 삭제됐으므로 이 검사를 통과한다고 복구 가능하다고 선언하지 않습니다.

[사용법]
1. ZIP 전체를 압축 해제합니다.
2. RUN_Day12_Cloud_Recovery_Preflight_READ_ONLY.cmd를 한 번 실행합니다.
3. 두 번 나오는 Windows 폴더 선택에서 각각 Google Drive에 표시되는
   **내 드라이브(My Drive)** 폴더, Microsoft **OneDrive** 폴더를 선택합니다.
   (클라우드 실제 로그인 계정과 일치하는 폴더인지 사용자가 확인.)
4. 완료 후 바탕화면 Geumyi-Cloud-Preflight-YYYYMMDD-HHmmss 폴더에서
   DAY12-CLOUD-PREFLIGHT-SHARE-ONLY-THIS.json 파일 **하나만** 이 채팅에 첨부하세요.
5. 결과가 BLOCKED여도 서버를 재시작하지 말고, Google Drive/OneDrive 폴더 또는
   기존 GSC server.json 설정을 임의 이동/수정하지 마세요. 이유 코드로 조정합니다.

[검사 범위]
- 운영 GSC Host 서비스 상태 및 기존 %ProgramData%\GeumyiServerCenter\server.json의
  프로필 ID와 서버 경로 존재 여부만 **읽습니다**.
- Wild/Playground/Lobby 루트 발견 여부, Other 설정 존재 여부만 상태로 저장합니다.
- 두 클라우드 폴더 존재, OneDrive 환경변수 경로와 일치 여부,
  GoogleDriveFS/OneDrive 프로세스 존재 여부를 분류합니다.
- 실제 디스크와 클라우드 쿼터, Google/OneDrive 동기화 완료, 월드 일관성,
  ZIP 압축/암호화/업로드/해시 검증/테스트 복원은 **하지 않습니다**.
- 설정 파일 원문, 사용자 이름, 월드/절대경로, 서버 IP, 토큰, 비밀번호 등을
  공유용 JSON에 넣지 않습니다.

[다음 단계]
- 서버별 월드는 원본 실행 중 단순 동기화하면 손상될 수 있습니다.
  온라인 서버는 저장 일관성 (Paper save-all flush 등 또는 정상 종료/스냅샷)
  확보 후 백업을 만들어야 합니다. 이번 1단계에서는 수행하지 않습니다.
- 백업 ZIP에는 GSC 비밀번호·인증 토큰·플레이어 정보가 있을 수 있으므로
  암호화된 형태로 사설 클라우드에 저장해야 합니다. GitHub나 채팅에 올리지 않습니다.
- Google Drive가 '파일 스트리밍'이면 가상 드라이브라도 임시 업로드 캐시가
  로컬 PC 용량을 소비할 수 있습니다. 2TB/1TB 요금제는 PC 여유용량 증거가 아닙니다.
- 실제 복구가 가능함을 확인하기 전에는 최종 Stable의 12.7/12.11/12.5
  실서버 변경/자동 서명 배포 게이트를 PASS 처리하지 않습니다.

[v3 개선 / 2026-10-14 오전 1:20 실제 검사에 따른 수정]
- 기존 검사 결과: Google Drive와 OneDrive 실행 프로세스 모두 발견, Google Drive 선택 폴더 오류 없음.
  그러나 OneDrive는 폴더 선택/접근 오류, Wild/Playground/Lobby GSC 루트 0/3 확인.
  이는 월드 손상 또는 서비스 중단의 증거가 아닙니다.
- v3는 GSC 설정의 직접 path/path_file이 열리지 않을 때만 GSC Host가 이미 해석한
  /api/settings 로컬 GET을 추가 사용합니다. 서버 설정, 토큰, 경로 원문은 공유 JSON에 기록하지 않습니다.
- OneDrive 폴더 선택 창에서 취소했거나 선택할 수 없는 경우, Windows에 OneDrive 환경 폴더가
  정확히 1개일 때만 **Y를 직접 입력**하여 그 기존 폴더를 사용할 수 있습니다.
  실제 본인 OneDrive 계정과 같은지 확인한 뒤 Y를 입력하세요.
- 서버별 root_resolution_method 및 gsc_settings_local_readonly_status가 새로 기록되어
  경로 접근/설정 문제인지 좁혀볼 수 있습니다. API 401/403은 BLOCKED로 남습니다.
- **이전 v2 결과를 다시 보낼 필요는 없습니다.** 새 경로 해석 기법을 포함한 v3 검사 1회만 필요.
- 실제 클라우드 업로드·동기화·암호화·월드 백업 및 복원은 **여전히 미수행**입니다.
