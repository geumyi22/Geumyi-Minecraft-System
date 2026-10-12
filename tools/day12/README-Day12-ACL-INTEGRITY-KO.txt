금이 Day 12.5 - 로컬 ACL 백업 무결성 / 기존 ACL 재비교 [읽기 전용]

목적
- 서버 PC에 이미 저장된 기존 10개 ACL DACL 백업 원본의 SHA-256을 재검증
- 현재 ProgramData 및 GSC 대상 10개 DACL/소유자/상속 상태가 백업 당시와 같은지 확인
- BUILTIN_USERS 생성 허용 ACE가 상속/명시로 존재하는지 익명 집계
- 기존 GSC ACL, 서버, 파일, 방화벽, 서비스는 절대 변경하지 않음
- 운영 서버에서 icacls /restore를 실행하지 않음

실행 방법
1. 서버 PC에서 이 키트 ZIP을 압축 해제합니다.
2. START_Day12_Phase5_ACL_Backup_Integrity_READ_ONLY.cmd를 더블클릭합니다.
3. PASS면 기존 LOCALAPPDATA\Geumyi-Day12-ACL-Backup\backup-* 폴더에
   DAY12-ACL-INTEGRITY-SHARE-ONLY-THIS-*.json 파일이 새로 생성됩니다.
4. 위 이름의 새 JSON 하나만 대화에 업로드하세요.
5. 기존 PRIVATE-ACL-BACKUP-MANIFEST-DO-NOT-SHARE.json,
   PRIVATE-*.dacl 및 모든 원본 SID, 경로, SDDL은 PC 밖으로 공유하지 마세요.

주의
- 이 도구는 가장 최근의 private backup 폴더를 기본 선택합니다.
- 해시, DACL, 소유자, 상속 상태, 원본 파일 중 하나라도 변경되면
  작업을 중단합니다. 그 경우 ACL을 직접 바꾸거나 복원하지 마세요.
- 파일 생성은 보호된 기존 백업 폴더 안의 공유 가능한 진단 JSON 한 개뿐입니다.
- 출력 폴더의 기존 ACL을 변경하거나 private 원본을 덮어쓰지 않습니다.
- 정상 출력도 "복원 성공", "일반 사용자 쓰기 차단", "보안 완료"를 뜻하지 않습니다.
- 실서버 권한 적용은 별도의 명시적 승인 및 실제 계정별 권한 검토 이후에만 가능합니다.
