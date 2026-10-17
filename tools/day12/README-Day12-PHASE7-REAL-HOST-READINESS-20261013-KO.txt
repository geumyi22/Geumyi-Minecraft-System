Day12.7 실제 GSC Windows 서버 / 오프라인 기동 전 사전 안전 검사
2026-10-13 · READ ONLY · 기타(Other) 서버는 계속 의도적 OFFLINE

이 도구는 "오프라인 기동 실험" 자체를 하지 않습니다.
기존 Java 서버, GSC Host, 월드/백업/캐시/방화벽/ACL/네트워크 어댑터, 서명 릴리즈를 변경하지 않고
현재 GSC 상태와 안전한 Playground 단독 검증 가능성을 판단합니다.

[최신 사항]
- 이미 알려진 2026-10-10 10:58 테스트에서는 딱 한 가지:
  AUTOMATIC_UPDATE_POLICY_MUST_BE_REVIEWED 로 차단되었습니다.
- 위 보고서는 GSC 4.3.8 시점이며 현재 Host 버전/정책이 같다는 근거는 아닙니다.
- 이제 GSC Host 4.3.8과 4.5.1을 모두 지원하고, 그 외 버전이나 API 401은 차단합니다.
- 관리형 자동 업데이트 정책에서 서버를 함부로 재시작하면 기존 플러그인이 변경될 수 있으므로
  policy=managed/unknown일 때는 지금도 차단합니다. 강제로 hold/manual로 변경하지 않습니다.
- Golden 백업과 캐시의 과거 4/4, 84/84 무결성 실측은 재검사하지 않습니다.
- Other는 자동으로 시작하거나 종료하지 않습니다.

[실행]
1. 서버 PC에서 ZIP 전체 파일을 같은 폴더에 압축 해제하세요.
2. Day12_Phase7_Offline_Start_Readiness_READ_ONLY.cmd 한 번만 실행하세요.
3. 데스크톱 Geumyi-Day12-Offline-Readiness-*/Day12-Offline-Readiness-READ-ONLY.json
   파일만 이 채팅에 보내주세요. 비밀번호, 토큰, server.json, 원본 경로는 보내지 마세요.
4. PRECHECK_GUARDS_MET_NO_TEST_PERFORMED: 안전 조건이 증거 범위에서 충족됐다는 의미이며
   실제 오프라인 기동, 안전 롤백, Java/Bedrock 연결은 아직 검증되지 않았습니다.
5. BLOCKED_NEEDS_SAFETY_REVIEW: reasons 배열을 보고 다음 실험 방법을 바꿉니다.
   과거와 똑같이 관리형 자동 업데이트 정책 때문에 차단되면 다시 실행하지 마세요.

[실제 12.7 실험은 언제?]
- 가능하면 격리된 disposable/staging 프로필에서만 업데이트 출처 장애와 캐시 fallback을 검증합니다.
- 이미 GitHub Windows CI에서 GSC 4.5.1 + 실제 Paper 26.3 격리 업데이트 서버 장애·자동 복구는 통과했습니다.
- PROD 놀이터 재시작, 호스트 인터넷 단절, NIC/firewall 변경, 백업 또는 world 덮어쓰기,
  자동업데이트 정책 변경은 이 kit의 작업 범위가 아닙니다.
- CI PASS나 사전검사 PASS로 정식 Stable 최종 PASS를 선언하지 않습니다.
