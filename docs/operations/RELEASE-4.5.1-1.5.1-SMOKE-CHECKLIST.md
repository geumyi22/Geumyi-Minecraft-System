# GSC 4.5.1 / GSCM 1.5.1+151 — 실기기 설치 및 기능 점검

최신 [GitHub Stable 수동 설치 릴리즈](https://github.com/geumyi22/Geumyi-Minecraft-System/releases/tag/system-2026.10.11-stable-gsc451-gscm151).

**아직 실제 PC·휴대폰·Minecraft 서버에서 새 버전을 검증하지 않았습니다.** 아래 항목은 실행 전 모두 미완료이며 GitHub Actions CI 성공과 운영자 실기기 PASS를 구분합니다.

## 검증 근거와 범위

- [빌드 실행 #38084637534](https://github.com/geumyi22/Geumyi-Minecraft-System/actions/runs/38084637534): GSC/Android/iOS 구성요소 빌드 및 SHA-256 성공, GitHub 초안 태그 조회 오류로 최초 게시 단계 실패.
- [공개 실행 #38085210886](https://github.com/geumyi22/Geumyi-Minecraft-System/actions/runs/38085210886): GitHub release ID와 파일 10개·해시 검증 후 Latest Stable 공개 SUCCESS.
- 기존 운영 실기기 검증 버전: GSC Host/Client **4.3.8**, GSCM **1.1.5+117**. GitHub 최신 패키지는 수동 설치용이고 서명된 `deployment-stable.json`이 없으므로 GSC 자동 Stable 업데이트는 차단 상태입니다.
- `FINAL-RELEASE-GATES.json`의 실환경 보안·Maintenance Mode 게이트는 해제하지 않습니다.

## 운영자 체크리스트

- [ ] **사전 보호:** Golden 풀백업/복구 위치와 기존 4.3.8 설치본, GSCM 1.1.5+117 복구 수단 확인. 접속자·정비 시간을 확인하고 무인 작업 금지.
- [ ] **무결성:** 공식 GitHub 파일과 `SHA256SUMS-STABLE.txt`을 대조. 서명 불일치 APK, 출처 불명 파일 사용 금지.
- [ ] **GSC Client (관리 PC):** 4.5.1만 설치 → 연결/로그인 → 4개 서버 상태/알림/이벤트/업데이트 화면 확인 → 문제 시 이전 버전 복원.
- [ ] **GSC Host (서버 PC):** 별도 승인 후 4.5.1 설치 → 서비스, 원격 API, 클라이언트 연결, 서버 폴더·백업 무변경 확인. Minecraft/Paper/Velocity 동작은 별도로 확인.
- [ ] **업데이트 채널:** Beta 4.3.8, Stable의 서명된 manifest 부재 시 차단, Canary 다운그레이드 방지 등 안내가 정확한지 확인. 서명 검증을 우회하거나 가짜 manifest를 만들지 않음.
- [ ] **GSCM Android:** 사용자 승인으로 APK 설치 → 페어링/기존 연결/서버 제어 확인 → 앱 시작 시 업데이트 확인 켜기/끄기 및 '지금 업데이트 확인' 기능 확인. 비밀번호나 토큰을 로그에 올리지 않음.
- [ ] **GSCM iOS:** 미서명 IPA는 그대로 일반 설치할 수 없음. Apple 서명·프로비저닝이 준비된 경우에만 설치·기기 테스트 후 결과 기입; 미수행 시 SKIP.
- [ ] **Via 플러그인:** 먼저 Staging만 수행해 실제 JAR이 바뀌지 않는지 확인. 실제 적용이 필요하면 **4개 서버 모두 완전히 종료됐는지** 확인(등록된 서버만 자동 검사될 수 있으므로 로비 등 별도 확인). 승인·백업·해시 확인 후 오프라인 적용. 이후 수동 기동하여 Via JAR 로드/중복 플러그인/Java·Bedrock 호환성/접속을 검증. 재기동 뒤 오류는 자동 복원되지 않으므로 백업으로 수동 복구.
- [ ] **Geyser/Floodgate:** Via 오프라인 적용과 기존 프록시 rolling 적용은 별개. 변경할 필요가 없다면 건드리지 않음.
- [ ] **종료:** Java/Bedrock 접속, 서버 간 이동·위치 복원, 리소스팩 적용, GSCM 제어, 백업/로그/복구 확인. 운영자가 서명한 PASS/FAIL/SKIP 기록으로만 실제 환경 승인.

**결과 기입:** 날짜, PC/OS/앱 버전, 항목별 PASS/FAIL/SKIP, 민감정보 제거한 로그와 롤백 결과만 기재. 테스트하지 않은 항목은 완료 표시하지 않습니다.
