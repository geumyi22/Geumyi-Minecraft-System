Geumyi Server Center 5.1.1 — 개인용 Stable 설치 경로 수정

Host, Client, Setup의 제품 버전은 5.1.1입니다.
5.1.0에서 제공된 서버 7종 + 새 Velocity 관리 기능을 보존하며,
5.0.0 운영 Host에서 업그레이드하는 경우의 설치 보호 검사를 수정했습니다.

기존 GSC 5.0.0 -> GSC 5.1.1:
- 설치 전 실행 중인 기존 Host /api/health 응답과 role.json의 버전이
  5.0.0으로 일치하는지 검사합니다.
- Host service=true, ok=true, generation=4가 모두 확인되어야 합니다.
- Host가 중지되거나 응답하지 않으면 서비스를 변경하지 않고 중단합니다.
- 저장/실행 버전이 다르거나 4.5.2 Canary이면 계속 설치를 차단합니다.
- Windows 작업 스케줄러 소유 Velocity 3개와 Minecraft 월드·플레이어
  데이터는 새 인스턴스 관리 기능으로 자동 이전하지 않습니다.

중요: 이는 설치 사전검사와 버전 업그레이드 경로의 유지보수입니다.
실제 운영 PC 업그레이드는 별도 사전 백업, 기존 서비스 건강 확인,
플레이어가 없는 점검 시간, 설치 완료 후 구동/백업/복구 재검증이
필요합니다. 중지된 Host의 신원 검사를 임의 우회하지 마세요.

새 기능: Paper, Spigot, Purpur, Vanilla, Fabric, Forge, NeoForge 설치,
새 GSC 소유 Velocity의 시작/정상 종료/재시작, 로그·콘솔·Java
선택/다운로드, 기존 서버 가져오기, 원본 파일 보존형 등록 해제.

기존 GSCM 및 연동 플러그인 버전은 변경하지 않습니다.
기존 공개 GSC 5.0.0과 5.1.0 릴리스 및 서명 자산은 별도 보존됩니다.
SHA-256과 Ed25519 배포 메타데이터 서명 검증은
Windows Authenticode 코드 서명을 의미하지 않습니다.
