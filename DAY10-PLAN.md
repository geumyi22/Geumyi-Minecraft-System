# Day 10 — Full E2E + Lobby Network Plan

기준일: 2026-09-30

## 1. Day 10 목표

Day 10은 Day 8~9에서 만든 안전 업데이트/rollback 기반을 실제 다중 서버 네트워크에 연결하고,
Wild/Playground의 기존 월드와 게임플레이를 건드리지 않은 채 Lobby를 새 진입점으로 추가한다.

완료 선언은 실제 서버 PC Final E2E가 PASS한 뒤에만 한다.

## 2. 고정 제약

- Wild / Playground 기존 월드와 게임플레이 로직은 변경하지 않는다.
- Technology 0.1.4와 Chemistry 0.4.1은 Wild 전용이다.
- 기존 서버 시작은 각 서버의 `start.bat`을 유지한다.
- GSC의 Day 9 transaction / backup / post-start health / rollback 동작을 훼손하지 않는다.
- 네트워크/업데이트 조회 실패만으로 known-good 서버 시작을 막지 않는다.
- Java와 Bedrock 모두 같은 Lobby 진입 규칙을 사용한다.
- 테스트하지 않은 항목을 완료로 기록하지 않는다.

## 3. 최종 사용자 이동 규칙

### 외부에서 접속

모든 공개 접속점은 Proxy로 들어간다.

```text
Java / Bedrock
      |
    Proxy
      |
    Lobby
```

- 최초 접속은 항상 Lobby.
- Lobby에 들어올 때마다 중앙 Spawn으로 이동한다.
- 사용자가 예전 Wild/Playground 접속 주소를 사용해도 실제 backend에 직접 연결하지 않고 Proxy/Lobby로 수렴시킨다.
- backend 서버 포트는 외부에 직접 노출하지 않는다.

### Lobby -> backend

```text
Lobby
  |-- Wild       -> Wild에서 마지막으로 있던 위치
  |-- Playground -> Playground에서 마지막으로 있던 위치
  '-- Other      -> 해당 서버 마지막 위치 (향후)
```

저장된 위치가 없거나 안전하지 않으면 해당 서버 기본 Spawn으로 이동한다.

### backend -> Lobby

- `/lobby`, Lobby 이동 아이템/메뉴, 향후 GSC maintenance routing 모두 같은 경로를 사용한다.
- backend를 떠나기 직전에 해당 서버 마지막 위치를 저장한다.
- Lobby 도착 후에는 항상 Lobby 중앙 Spawn으로 이동한다.

## 4. 직접 backend 접속 처리

사용자에게 보이는 동작은 "Wild/Playground로 바로 들어가도 Lobby 중앙"이다.

구현은 backend에서 플레이어를 뒤늦게 튕겨 보내는 방식보다 다음을 우선한다.

1. Proxy만 외부에 공개한다.
2. Wild/Playground는 같은 PC에서 `127.0.0.1:<port>`로만 수신한다.
3. Windows Firewall에서도 backend 포트의 외부 직접 접근을 차단한다.
4. 기존 공개 Wild/Playground 주소가 있다면 Proxy 쪽 진입점으로 전환해 Lobby로 보낸다.
5. Velocity modern forwarding + secret을 사용한다.

이 방식은 backend가 offline-mode가 되는 proxy 구조에서 직접 접속/UUID 사칭 위험도 같이 차단한다.

## 5. 네트워크 구조

```text
                         +----------------+
Java TCP -------------->|                |
                         |    Velocity     |----> Lobby
Bedrock UDP -> Geyser -->|    + Floodgate |----> Wild
                         |                |----> Playground
                         +----------------+----> Other (future)

Backend listeners: localhost/private only
```

우선 설계:
- Proxy: Velocity
- Player forwarding: Velocity modern
- Geyser: Proxy에만 설치
- Floodgate: Proxy에 설치. backend에서 Floodgate API가 필요한 경우에만 backend 설치를 재검토
- Lobby/Wild/Playground: Paper 계열 backend
- backend 버전과 Geyser가 요구하는 Java protocol 차이가 있으면 ViaVersion 적용 여부를 공식 지원표 기준으로 결정

## 6. Lobby 맵 범위

새로 만드는 맵은 Lobby 하나뿐이다.

목표:
- 가볍고 빠르게 로드되는 기본 서버 Lobby
- 중앙 Spawn
- Wild / Playground 선택 구역
- 서버 상태 표시
- 나침반 또는 간단한 서버 선택 GUI
- 필요 시 NPC/표지판 추가
- PvP, 블록 파괴/설치, 아이템 드롭, 허기, 낙하 피해 등 Lobby 불필요 동작 차단
- 맵 밖 추락 방지
- 과도한 장식/대형 월드 생성은 하지 않는다

Lobby 월드는 재현 가능하게 관리한다. 월드 바이너리만 수작업으로 의존하지 않고,
필요한 핵심 구조/Spawn/보호 설정을 버전 관리 가능한 Lobby 플러그인/설정으로 유지한다.

## 7. Last Location 설계

위치는 서버별로 분리한다.

```text
UUID
server_id
world
x
y
z
yaw
pitch
saved_at
```

저장 시점:
- Lobby 이동 직전
- 다른 backend 이동 직전
- Player quit
- 정상 서버 종료 전 가능한 범위
- 필요 시 저빈도 주기 저장

복귀 검증:
1. world 존재
2. 좌표 범위 유효
3. chunk load 가능
4. 안전한 도착 지점 확인
5. 실패 시 해당 서버 기본 Spawn

Lobby 위치는 저장/복원하지 않는다. Lobby join은 항상 중앙 Spawn이다.

## 8. GSC server catalog 확장

GSC가 `wild`, `playground`만 특별 취급하지 않도록 server catalog를 일반화한다.

예시:

```json
{
  "id": "lobby",
  "role": "lobby",
  "managed": true,
  "update_policy": "managed"
}
```

역할:
- lobby
- wild
- playground
- other

컴포넌트 대상 규칙은 기존대로 유지한다.
- GST/GDS: 정책에 따라 공통
- Technology/Chemistry: Wild only
- Lobby 전용 플러그인: Lobby only

## 9. 서버 상태와 이동

Proxy/Lobby는 GSC 상태를 참고해 backend 이동 가능 여부를 판단한다.

최소 상태:
- ONLINE
- STARTING
- STOPPING
- MAINTENANCE
- UPDATING
- HEALTH_CHECK
- ROLLING_BACK
- OFFLINE
- FAILED

ONLINE만 정상 이동 대상으로 취급한다.
나머지는 Lobby에 남기고 간단한 상태 메시지를 표시한다.

Day 10에서는 안전한 차단/복귀 기반까지 구현하고,
player-aware countdown/maintenance scheduling은 Day 11 범위로 둔다.

## 10. Day 10 Full E2E

### A. 배포/rollback
- clean test install
- 기존 설치 upgrade
- 정상 update
- corrupt artifact
- signature/hash failure
- GitHub/update lookup outage
- transaction interruption
- post-start health failure -> rollback
- previous known-good server recovery

### B. 서버 분리
- Wild-only component가 Playground/Lobby에 배포되지 않음
- Lobby 전용 component가 Wild/Playground에 배포되지 않음
- server catalog에서 새 서버 추가 가능

### C. Java 이동
- 외부 접속 -> Lobby 중앙
- Lobby -> Wild 마지막 위치
- Wild -> Lobby 중앙
- Lobby -> Playground 마지막 위치
- backend 직접 public bypass 불가
- backend offline/maintenance 시 Lobby 잔류

### D. Bedrock 이동
- Bedrock -> Geyser on Proxy -> Lobby 중앙
- Lobby -> Wild/Playground 이동
- 다시 Lobby 복귀
- 마지막 위치 복원
- Java/Bedrock UUID/위치 데이터가 충돌하지 않음

### E. 상태 복구
- Final E2E 전후 Wild/Playground 실행 상태 복원
- updater 설정 복원
- 임시 테스트 artifact/설정 제거
- 결과 JSON + 로그 작성

## 11. 작업 단계

### Phase 0 — 기준선/설계 고정
- Day 9 완료 상태 문서화
- Day 10 본 문서 고정
- 현재 설정/포트/서버 경로 drift 검사
- 최신 Velocity/Geyser/Floodgate/Paper 호환성 확인

### Phase 1 — Full deployment E2E harness
- clean/update/rollback/failure injection을 실서버와 분리된 테스트 환경에서 자동화

### Phase 2 — Multi-server foundation
- GSC server catalog 일반화
- Lobby/Other 역할과 component targeting 추가

### Phase 3 — Proxy + Lobby
- Velocity 설치/설정
- modern forwarding
- backend localhost/firewall 보호
- Geyser/Floodgate proxy 배치
- Lobby Paper 서버 및 Lobby 맵/플러그인

### Phase 4 — Last Location + routing
- 서버별 위치 저장/복원
- /lobby
- Lobby 서버 선택 UI
- 상태 기반 이동 차단

### Phase 5 — 실제 Java/Bedrock E2E
- 사용자 PC에서 실제 접속/이동 검증
- 문제 수정 후 반복

### Phase 6 — Day10 Final E2E
- `Day10_Final_E2E.cmd`
- 실제 서버 PC PASS 후에만 Day 10 완료 처리

## 12. 완료 조건

- [ ] Day 9 기준선/문서 drift 정리
- [ ] Full deployment E2E harness PASS
- [ ] GSC generic server catalog PASS
- [ ] Velocity + modern forwarding PASS
- [ ] backend direct exposure 차단 확인
- [ ] Lobby 서버 부팅 PASS
- [ ] Lobby 중앙 Spawn 규칙 PASS
- [ ] Lobby 맵/선택 UI PASS
- [ ] Wild 마지막 위치 복원 PASS
- [ ] Playground 마지막 위치 복원 PASS
- [ ] Java 전체 이동 E2E PASS
- [ ] Bedrock 전체 이동 E2E PASS
- [ ] maintenance/offline 이동 차단 PASS
- [ ] update/rollback과 Lobby routing 공존 PASS
- [ ] Day10 Final E2E 서버 PC PASS
- [ ] 문서/rollback 절차/변경 내역 반영
