# GSC 5.1.1 — 개인용 Stable 설치 이전 경로 수정

**GSC 5.1.0 설치기가 정상적으로 실행 중인 5.0.0 Host를 허용하지 않는 문제를 수정한 유지보수 릴리스입니다.** 기존 5.0.0과 5.1.0 배포 파일·태그·서명은 수정하지 않습니다.

## 수정한 오류

기존 5.1.0 설치기는 `role.json`의 `version=5.0.0`과 실행 중인 `/api/health`의 `version=5.0.0`이 일치하더라도 5.0.0을 허용 대상에서 제외했습니다. 이번 릴리스는 **실행 중인 기존 5.0.0 Host**가 `ok=true`, `service=true`, `generation=4`이고 저장된 역할 버전과 일치하면 제한된 5.1.1 이전 검사를 통과하도록 수정합니다.

- Host가 **Stopped**이거나 응답하지 않는 경우, 기존 서비스부터 정상 시작·진단해야 합니다. 설치기는 이를 자동으로 우회하지 않으며 서비스 변경 전에 중단합니다.
- `role.json`과 실행 중 Host 버전 불일치, 알 수 없는 이전 버전, 4.5.2 Canary, Health 검증 실패와 API 세대 불일치는 **계속 차단**합니다.
- 확인 응답 대기 상한을 1.8초에서 **5초**로 늘리고 Host 미응답과 검증 실패를 구분해 표시합니다.
- 이번 수정은 기존 보호 검사를 삭제하지 않고, 5.0.0→5.1.1과 5.1.0→5.1.1를 **명시적으로 허용**한 것입니다.

## 유지한 5.1 기능

Paper / Spigot / Purpur / Vanilla / Fabric / Forge / NeoForge 등 7종 게임 서버 관리, 새 GSC 소유 Velocity 생성·시작·정상 종료·재시작, 기존 폴더 가져오기·콘솔·로그·Java 자동 준비와 파일을 삭제하지 않는 등록 해제.

**기존 야생·놀이터·기타 Velocity 3개의 운영 주체는 계속 Windows 작업 스케줄러입니다.** 기존 프록시용 종료 플러그인을 적용하려면 이용자 없는 안전한 시간에 기존 방식으로 한 차례 정상 종료한 후 오프라인 설정을 준비해야 합니다. 자동 강제 종료나 운영 서버 소유권 이전은 포함하지 않습니다.

## 배포·검증 범위

GitHub 릴리스에 첨부된 Windows Setup·Host·Client는 **정확한 소스 커밋의 Windows CI**에서 새로 빌드됩니다. 릴리스의 `SHA256SUMS.txt`, `deployment-stable.json` 및 Ed25519 `deployment-stable.json.sig`로 출처·파일 크기·무결성을 검증할 수 있습니다. 이는 **Windows Authenticode EXE 코드 서명이 아닙니다**.

릴리스 CI에는 Windows 서비스/인증 API, 실제 Windows PE Setup 패키징과 일회용 테스트 환경의 백업·롤백, 5.0.0·5.1.0 호스트에 대한 마이그레이션 허용/거부 테스트를 포함하도록 설정했습니다. **CI와 제한적 테스트 통과가 실운영 Windows PC의 실제 5.0.0→5.1.1 서비스 교체·게임 플레이·라이브 롤백을 검증했다는 의미는 아닙니다.**

## 설치 전 중요한 주의사항

이미 작동하는 **GSC 5.0.0 Host를 삭제하거나 강제로 종료하지 마세요.** 업그레이드 작업은 서비스 정지·파일 교체 및 방화벽/설정 갱신을 수행할 수 있으므로 먼저 다음을 확인해야 합니다.

1. 기존 Host 서비스 `Running`, `/api/health`에서 **5.0.0 / ok=true / service=true / generation=4**, `role.json`에서 **role=3 / version=5.0.0** 확인.
2. Minecraft 서버·월드·플레이어 파일과 GSC 설정·기존 설치 실행 파일 및 Scheduled Tasks를 **복구 가능한 별도 백업**으로 보존.
3. 접속자가 없는 안전한 점검 시간에 설치·서비스 재시작을 진행하고, 설치 후 GSC Host/Client·기존 월드·Java/Bedrock 접속·저장·백업을 검증.
4. 업데이트 중 실패 시 원래 설정·프로그램/서비스로 복구 가능한지 검토하고, 정상 상태라면 **5.0.0을 계속 사용해도 됩니다**. 강제 제거·보호 비활성화·세계 초기화는 해결책이 아닙니다.

기존 개인용 5.0 Stable의 사용자 실플레이 PASS는 5.1.1에 자동으로 승계되지 않습니다. 실제 운영 PC 5.1.1 설치, Microsoft 계정 플레이, WAN/GSCM 모바일, 장시간 다중 접속, 라이브 월드 복원은 별도 검증이 필요합니다. 정식 전체 프로젝트 `FINAL-RELEASE-GATES.json`는 여전히 미충족 상태로 보존합니다.

관련 자료: [이전 5.1.0 개인용 Stable](https://github.com/geumyi22/Geumyi-Minecraft-System/releases/tag/gsc-v5.1.0), [기존 5.0 Stable](https://github.com/geumyi22/Geumyi-Minecraft-System/releases/tag/gsc-v5.0.0), [5.1.1 제한적 수락 기록](../../deploy/gsc-5.1.1-personal-acceptance.json).
