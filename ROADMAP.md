# Geumyi Minecraft System — 작업 로드맵

기준일: 2026-09-27

| Day | 목표 | 상태 |
|---|---|---|
| 1 | GitHub 소스 복구·정리, 최신 버전 기준 통일 | 완료 |
| 2 | GSC / GDS / ResourcePack System CI 구축 및 실제 Actions 성공 확인 | 완료 |
| 3 | GST HOTFIX·StatusAgent·Technology·Chemistry 복구, Wild/Playground 설정 근거 회수, Public 보안 점검 | 완료* |
| 4 | 실제 Wild/Playground 서버 E2E 부팅 및 플러그인/리소스팩/연동 검증 | 예정 |
| 5 | GSC/GSCM 통합 안정화: 재연결, Whole Shutdown, 락, 고아 프로세스, 상태 오탐, 네트워크 복구 | 예정 |
| 6 | GSCM Android+iOS 실기기 검증: 페어링, 토큰 지속, WS/HTTP 재동기화, 제어·재접속 | 예정 |
| 7 | GSC/GST/GDS/Agent/Technology/Chemistry/GSCM 자동 빌드 체계 정리 | 예정 |
| 8 | 자동 Release/업데이트/체크섬/패키징 표준화 | 예정 |
| 9 | 서버·설정 백업/복원/롤백 및 실패 복구 테스트 | 예정 |
| 10 | 최종 장애/E2E 테스트 + 문서/Release 마감 + 로비 중심 멀티서버 네트워크 설계 | 예정 |

## Day 3 완료 기준

Day 3의 복구/검증 단계는 완료했습니다. 다만 Wild/Playground의 **정확한 2026-09-26 실서버 설정**은 보존 자료만으로 증명할 수 없으므로, Day 4 실제 서버 E2E에서 서버 PC의 현재 설정을 캡처해 확정합니다. 이 제한은 복구 실패를 숨기지 않고 별도로 유지합니다.

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
