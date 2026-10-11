금이 Day 12.5 — GSC ACL 원본 백업 / 생산 환경 읽기 전용

목적:
실서버의 GSC ACL을 바꾸기 전에, 대상 10곳의 기존 DACL을 icacls /save
로 개별 저장합니다. 백업 결과는 로컬 사용자 프로필의 새 보호 폴더에
두며, 기존 ProgramData/GSC ACL이나 서비스·서버·월드·Golden 백업은
수정하지 않습니다.

서버 PC에서 실행:
1. 이 ZIP을 원하는 작업 폴더에 압축 해제합니다.
2. START_Day12_Phase5_Production_ACL_Backup_READ_ONLY.cmd를 더블클릭합니다.
3. 실행 후 탐색기에 표시되는 Geumyi-Day12-ACL-Backup 폴더에서
   가장 최근 backup-* 폴더를 엽니다.
4. DAY12-ACL-BACKUP-SHARE-ONLY-THIS.json 파일 하나만 대화에 올리세요.
5. PRIVATE-*.dacl, PRIVATE-*.json 원본 백업은 절대 업로드하지 말고
   해당 서버 PC에 그대로 보관하세요. 사용자 경로, SID, 권한 정보 포함.

검사 대상:
GSC 루트, Runtime, Runtime/Agent, server.json (4개 필수),
trusted-devices.json, Updates, Backups, Staging, Staging/GSC, Agent JAR
(6개 선택 대상); ProgramData 부모 ACL은 변경 전/후 읽기로만 확인.

안전 범위:
- GSC의 기존 ACL을 읽기만 함. icacls /save를 사용하되 /restore는 하지 않음.
- 재귀 스캔(/T), 모든 사용자 권한 일괄 제거, 서버 재시작 절대 금지.
- LOCALAPPDATA에 생성하는 새 결과 폴더만 ACL 접근 제한 설정.
- DACL 백업은 소유자/SACL/MIC까지 복구하는 완전한 백업이 아님.
- 특정 임의 파일 복구는 테스트하지 않았고, 작업 성공이 보안 PASS는 아님.
- 권한 적용은 원본 세부 ACE 확인, 정확한 롤백 검증, 사용자 별도 승인 후만 수행.

오류가 발생하면 CMD 화면만 공유하세요. 개인 정보가 담긴 원본은
GitHub나 대화에 올리지 마세요.
