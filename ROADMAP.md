# Geumyi Minecraft System — 작업 로드맵

기준일: 2026-09-28

| Day | 목표 | 상태 |
|---|---|---|
| 1 | GitHub 소스 복구·정리, 최신 버전 기준 통일 | 완료 |
| 2 | GSC / GDS / ResourcePack System CI 구축 및 실제 Actions 성공 확인 | 완료 |
| 3 | GST HOTFIX·StatusAgent·Technology·Chemistry 복구, Wild/Playground 설정 근거 회수, Public 보안 점검 | 완료 |
| 4 | 실제 Wild/Playground 서버 E2E 부팅 및 플러그인/리소스팩/연동 검증 | 완료 |
| 5 | GSC/GSCM 통합 안정화: 재연결, Whole Shutdown, 락, 고아 프로세스, 상태 오탐, 네트워크 복구 | 완료 |
| 6 | GSCM Android+iOS 실기기 검증: 페어링, 토큰 지속, WS/HTTP 재동기화, 제어·재접속 | 완료 |
| 7 | GSC/GST/GDS/Agent/Technology/Chemistry/GSCM 자동 빌드 체계 정리 | 예정 |
| 8 | 자동 Release/업데이트/체크섬/패키징 표준화 | 예정 |
| 9 | 서버·설정 백업/복원/롤백 및 실패 복구 테스트 | 예정 |
| 10 | 최종 장애/E2E 테스트 + 문서/Release 마감 + 로비 중심 멀티서버 네트워크 설계 | 예정 |

## Day 3 완료 기준

Day 3의 복구/검증 단계는 완료했습니다. 당시 남겨 둔 Wild/Playground 실서버 설정 확인 항목은 Day 4에서 서버 PC의 2026-09-27 현재 설정을 캡처해 공개용으로 정리했습니다.

## Day 4 완료 기준

Wild/Playground Paper 26.3 실서버 부팅, GSC 4.2.3, GSCM 1.1.2, StatusAgent 0.5.4, GST 1.1.1 HOTFIX, GDS 1.1.1의 실제 상태/연동 증거를 확인했습니다. 세부 근거와 비차단 이슈는 `DAY4-E2E-REPORT.md`에 기록합니다.

Day 4는 **완료**로 닫습니다.

후속 항목 처리 상태:
- Bedrock/Geyser 문제: 사용자 보고 기준 해결
- Playground AutoSaveWorld 오류: 사용자 보고 기준 해결
- ProtocolLib 26.3 경고: 사용자 보고 기준 해결
- DiscordSRV 누락 설정: V2 자동 보정 로그에서 92개 누락 키 추가 확인, 사용자 승인으로 통과
- resource-pack SHA1: 자동 검증 성공은 확인하지 못했으나 사용자 승인으로 Day-4 비차단/통과 처리. 기술적 검증 완료로 기록하지 않음

## Day 5 완료 기준

Day 5는 **사용자 실사용 검증 통과**로 완료 처리합니다. 시작/종료/재시작/강제 종료, 중복 명령 및 락, GSC/Agent 재연결, 네트워크 복구, Whole Shutdown, 고아 프로세스 여부, Other 서버 상태/알림 동작을 사용자가 기존 운영 중 이미 확인했고 모두 정상이라고 확인했습니다.

새로운 Day-5 로그 재수집이나 별도 assistant-side E2E 재현은 수행하지 않았으므로, 이를 새로 재현된 자동 테스트 결과로 기록하지 않습니다. 세부 경계는 `DAY5-STABILITY-REPORT.md`에 기록합니다.

## Day 6 완료 기준

Day 6은 **완료**로 닫습니다. Android와 iOS에서 페어링, 인증정보 지속, 앱 재실행/기기 재부팅, HTTP snapshot, WebSocket realtime, 네트워크 끊김/자동 복구, 백그라운드 복귀, 서버 시작/종료/재시작, 로그아웃/토큰 해제를 사용자 실기기 기준으로 확인했습니다.

Android에서는 오프라인인데 상단이 `REALTIME`으로 남는 표시 문제를 재현했고, GSCM 1.1.2+113에서 수정 후 실기기 재검증까지 통과했습니다. Android CI의 고정 서명키 문제는 Day 8 Release/패키징 범위로 남깁니다.

## Day 10 — 로비/서버 이동 설계

목표 구조:

```text
                    Lobby
              /       |       \
           Wild   Playground   Other
              \       |       /
                 Lobby return
```

설계 시 확인할 항목:

- Paper 26.3의 `accepts-transfers` / Minecraft Transfer 기능을 실제 운영에 사용할지 검증
- 필요 시 Velocity 등 프록시 방식과 Transfer 방식 비교
- Java + Bedrock(Geyser/Floodgate) 이동 호환성 확인
- 로비 NPC / 아이템 메뉴 / 명령어 중 서버 선택 UX 결정
- GSC의 서버 상태와 연결해 OFFLINE 서버 이동 차단 또는 시작 요청 흐름 검토
- Lobby / Wild / Playground / Other를 하나의 서버군으로 관리하는 GSC 모델 검토
- 서버별 인벤토리·월드·플러그인·권한 분리 정책 결정
- 다른 서버에서 Lobby로 되돌아오는 흐름 포함
- 실제 네트워크 구성도와 장애 시 fallback 동작 작성

현재 회수된 Wild/Playground 2026-09-10 설정 근거에는 `accepts-transfers=true`가 이미 존재하지만, **최종 방식은 실제 서버 E2E와 Java/Bedrock 호환성 검증 후 확정**합니다.
