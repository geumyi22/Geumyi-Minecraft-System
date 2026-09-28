# Geumyi Minecraft System — Build, Release & Auto-Deployment Architecture

기준일: 2026-09-28

## 목표

ChatGPT에서 소스를 수정해 GitHub에 반영한 뒤, 사람이 JAR/APK/설정 파일을 매번 직접 복사하지 않아도 다음 흐름으로 안전하게 운영하는 것이 목표입니다.

```text
Source change
  -> GitHub main
  -> component CI / tests
  -> verified artifact
  -> signed deployment manifest
  -> Stable/Beta/Canary channel
  -> server pre-start updater
  -> staging download
  -> checksum/signature verification
  -> backup + atomic replacement
  -> Minecraft start
  -> post-start health verification
  -> success OR automatic rollback
```

중요 원칙은 **CI 실패, 다운로드 실패, 검증 실패, 설치 실패가 Minecraft 서버 자체의 시작을 막지 않도록 하는 것**입니다. 새 버전이 안전하다고 증명되지 않으면 마지막 정상 버전을 계속 사용합니다.

## 1. 관리 대상

### 자체 관리 — 자동 배포 가능

- GeumyiServerTools (GST)
- GeumyiDiscordStatus (GDS)
- GeumyiTechnology
- GeumyiChemistry
- GeumyiStatusAgent
- GSC
- GSCM Android
- GSCM iOS build artifacts
- 자체 데이터팩
- 자체 리소스팩
- 향후 Lobby 전용 플러그인/브리지

### 외부 구성요소 — 기본은 자동 교체 금지

- Paper
- Geyser / Floodgate
- ProtocolLib
- DiscordSRV
- AutoSaveWorld
- 기타 외부 플러그인
- Java Runtime

외부 구성요소는 버전 감지/업데이트 알림은 가능하지만, 기본 정책은 `notify` 또는 `manual-approve`입니다. 특정 항목만 allowlist로 자동 업데이트를 허용합니다.

## 2. Release channel

각 컴포넌트는 다음 채널을 지원합니다.

- `stable`: 실서버 기본값. 전체 CI/검증 통과 버전만 승격.
- `beta`: 신규 기능 검증용.
- `canary`: 한 서버 또는 테스트 서버에 먼저 배포.
- `pinned`: 특정 버전 고정.
- `hold`: 새 버전이 있어도 현재 버전 유지.

Wild/Playground/Other/Lobby가 서로 다른 채널 또는 버전 pin을 가질 수 있도록 합니다.

## 3. Deployment manifest

배포의 source of truth는 branch가 아니라 **검증된 manifest**입니다.

예시:

```json
{
  "schema": 1,
  "channel": "stable",
  "generated_at": "2026-09-28T00:00:00Z",
  "components": {
    "technology": {
      "version": "0.1.4",
      "url": "...",
      "sha256": "...",
      "size": 123456,
      "requires_restart": true,
      "min_paper": "26.3",
      "targets": ["wild"]
    }
  }
}
```

최종 설계에서는 manifest 자체에도 서명을 붙입니다. updater에는 검증용 public key만 포함하고 signing private key는 GitHub Actions secret에만 보관합니다.

## 4. 서버 시작 전 updater

Minecraft `start.bat`을 직접 복잡하게 만들기보다 GSC가 서버 시작 전에 updater 단계를 실행하는 구조를 우선합니다.

```text
GSC Start Request
  -> acquire update lock
  -> read server/component policy
  -> fetch deployment manifest
  -> compare current vs target
  -> download to staging
  -> verify SHA-256 + signature
  -> backup current files
  -> atomic replacement
  -> write deployment journal
  -> launch original start.bat
```

네트워크가 없거나 GitHub가 장애여도 기존 JAR로 서버를 시작합니다.

## 5. Transaction / rollback

모든 배포는 트랜잭션처럼 취급합니다.

- `.geumyi-update/staging/`: 다운로드 임시 위치
- `.geumyi-update/backups/`: 이전 정상 JAR
- `.geumyi-update/state.json`: 현재 설치 버전
- `.geumyi-update/journal.jsonl`: 배포 기록
- update lock: 동시에 두 번 업데이트 금지
- 부분 교체 금지
- 새 파일 검증 완료 전 기존 파일 삭제 금지

서버 시작 후 일정 시간 내 아래 조건을 만족하지 못하면 자동 롤백 후보가 됩니다.

- Paper 프로세스 정상 생존
- Java 포트 응답
- GDS 응답
- GST health 정상
- 치명적 startup exception 없음
- 필요 시 Agent/GSC heartbeat 정상

정책은 자동 롤백 / 알림 후 수동 롤백 중 선택할 수 있게 합니다.

## 6. Dependency & compatibility graph

플러그인 하나만 최신이면 되는 것이 아니므로 manifest에 호환성 정보를 둡니다.

예:

```text
Technology 0.1.4
  requires Paper >= 26.3
  compatible GST >= 1.1.1
  server = Wild only
```

의존성이 맞지 않으면 updater가 배포를 거부하고 기존 버전을 사용합니다.

여러 파일이 같이 바뀌어야 하는 경우 **release group**으로 묶어서 전부 성공할 때만 교체합니다.

## 7. GSC Update Center

GSC에 전용 업데이트 화면을 추가합니다.

표시 항목:

- 설치 버전
- Stable 최신 버전
- 상태: 최신 / 업데이트 가능 / 고정 / 보류 / 오류
- 대상 서버
- 마지막 업데이트 시각
- 마지막 rollback
- checksum/signature 결과
- restart 필요 여부

기능:

- 다음 시작 때 업데이트
- 지금 다운로드만
- 업데이트 보류
- 특정 버전 pin
- Stable/Beta/Canary 변경
- rollback
- 업데이트 이력
- 전체 서버 일괄 정책
- 서버별 override
- dry-run

## 8. GSCM mobile UX

GSCM에서도 Update Center의 상태를 읽을 수 있게 합니다.

- 업데이트 가능 알림
- 다음 재시작 때 적용 예약
- 서버별 channel/pin 조회
- rollback 요청
- 배포 진행률
- 실패 원인
- 서버 시작 후 health verification 결과

위험한 작업은 모바일에서 한 번 더 확인하도록 합니다.

## 9. Canary rollout

실서버 여러 대에 한 번에 배포하지 않습니다.

권장:

```text
Canary/Test
 -> Playground
 -> Wild
 -> Other
 -> Lobby
```

각 단계 health check가 성공한 경우에만 다음 대상으로 승격할 수 있게 합니다.

## 10. Maintenance window

자동 업데이트 적용 시점을 설정할 수 있습니다.

- next-start
- next-restart
- manual
- maintenance-window
- scheduled

플레이어가 있을 때 강제 업데이트/재시작하지 않는 정책도 둡니다.

예:
- 플레이어 0명일 때만 적용
- 최대 대기 시간
- Discord/GSCM 사전 알림
- 60/30/10초 countdown

## 11. Notification

이벤트:

- 업데이트 발견
- 다운로드 완료
- 검증 성공/실패
- 적용 성공
- health check 실패
- rollback
- pinned version이 오래됨
- 외부 플러그인 업데이트 발견

전달:
- GSC UI
- GSCM
- Discord Agent

중복 알림 방지와 이벤트 dedupe를 사용합니다.

## 12. Resource/Data pack

자체 리소스팩/데이터팩도 같은 배포 시스템에 포함할 수 있습니다.

리소스팩은:
- ZIP 생성
- SHA-1 계산
- SHA-256 저장
- URL/UUID 관리
- `server.properties`의 `resource-pack`, `resource-pack-sha1`, `resource-pack-id` 일관성 검증

을 자동화합니다.

## 13. GSC / Agent self-update

Minecraft 플러그인과 별도 단계로 구현합니다.

- 새 바이너리 다운로드
- 서명/해시 검증
- 현재 바이너리 백업
- helper/updater 프로세스로 교체
- 재실행
- health 확인
- 실패 시 이전 바이너리 복귀

Windows 서비스/자동시작 상태를 깨뜨리지 않아야 합니다.

## 14. GSCM distribution

### Android

Day 8에서 **고정 release signing key**로 전환합니다.

- signing key는 GitHub Secret/보안 저장소로 관리
- 같은 applicationId + 같은 signer 유지
- 이후 APK는 정상 in-place update 가능
- CI의 매 실행 랜덤 debug signer 사용 금지

### iOS

iOS는 unsigned IPA를 단순 자체 updater로 설치할 수 없으므로 서명/배포 방식에 따라 분리합니다.

- 개발/개인 설치: 로컬 Apple signing
- TestFlight/App Store 사용 시 해당 배포 채널
- 내부 서명 방식 사용 시 provisioning 만료/기기 등록 정책 별도 관리

GSC/GSCM은 업데이트 존재 여부와 빌드 artifact 상태를 보여줄 수 있지만 iOS 설치 정책은 Apple signing 체계를 따릅니다.

## 15. Supply-chain / security

장기적으로 다음을 포함합니다.

- pinned GitHub Action versions
- dependency scanning
- secret scanning
- SBOM 생성
- artifact SHA-256
- signed deployment manifest
- release provenance
- 최소 권한 GitHub token
- public repo에 private signing key 금지
- production secret과 source 완전 분리

## 16. Reproducibility

가능한 도구 버전을 고정합니다.

- JDK
- Go
- Flutter
- Android SDK/AGP/Kotlin
- build scripts

같은 commit에서 가능한 한 같은 산출물을 만들 수 있도록 빌드 환경 버전을 기록합니다.

GST처럼 legacy binary core가 필요한 컴포넌트는 완전 reproducible이라고 과장하지 않고 overlay/provenance 경계를 계속 기록합니다.

## 17. Cache / offline operation

- 마지막 정상 manifest 캐시
- 마지막 정상 artifact 보존
- 실패 다운로드 재사용 금지
- ETag/If-None-Match로 불필요한 다운로드 감소
- 동일 artifact는 서버별 중복 다운로드 대신 GSC cache 공유 가능
- GitHub/인터넷 장애 시 기존 버전으로 정상 부팅

## 18. Audit / observability

모든 업데이트 이벤트를 기록합니다.

- actor
- server
- component
- from/to version
- release channel
- artifact SHA-256
- manifest version
- 시작/완료 시간
- 결과
- rollback 여부
- 실패 원인

GSC activity log 및 GSCM activity 화면과 연동할 수 있습니다.

## 19. External update policy

외부 플러그인은 구성 파일로 정책화합니다.

예:

```yaml
paper: notify
geyser: manual
protocollib: manual
discordsrv: manual
some-safe-plugin: stable-auto
```

버전만 높다는 이유로 실서버에 자동 배포하지 않습니다.

## 20. 최종 UX 목표

성민님이 ChatGPT에서 수정 요청한 뒤의 운영 흐름은 다음처럼 단순해지는 것이 목표입니다.

```text
"Technology 기능 수정해줘"
        ↓
GitHub commit
        ↓
자동 build/test
        ↓
PASS -> Canary/Stable artifact
        ↓
GSC/GSCM: "Technology 0.1.4 업데이트 준비됨"
        ↓
다음 서버 시작
        ↓
자동 backup / verify / install
        ↓
server start
        ↓
health PASS
        ↓
완료 알림
```

실패 시:

```text
CI FAIL       -> 배포 안 됨
Download FAIL -> 기존 버전으로 시작
Hash FAIL     -> 설치 취소 + 기존 버전
Health FAIL   -> rollback + 알림
```

## 구현 단계

### Day 7 — Build foundation

- GST/GDS/Technology/Chemistry/Agent/GSC/GSCM component CI
- path filters
- build/test artifact naming
- toolchain version 정리
- component version metadata
- CI status 명확화
- verified artifact 생성

### Day 8 — Secure Release & Update foundation

- Release artifact 표준
- deployment manifest
- Stable/Beta/Canary
- SHA-256 + manifest signature
- Android persistent release signing
- pre-start updater
- staging/lock/cache
- GSC Update Center 1차
- 자체 플러그인 next-start auto-update

### Day 9 — Transaction / Backup / Rollback

- automatic backup
- atomic replacement
- journal
- post-start health verification
- automatic rollback
- dependency/release group
- failure injection tests
- offline/GitHub outage tests

### Day 10 — Full E2E + Lobby architecture

- clean install -> update -> rollback E2E
- Wild/Playground/Other cross-server deployment test
- final docs/release
- Lobby transfer architecture decision
- Java + Bedrock transfer compatibility
- update/restart behavior during Lobby routing

### Day 11 — Operations UX & Fleet management

- GSC full Update Center
- GSCM update controls
- per-server policy/channel/pin/hold
- maintenance windows
- player-aware restart
- canary promotion
- notifications
- update history/audit
- external plugin notify/manual policy
- dry-run

### Day 12 — Extended automation & production hardening

- GSC/Agent self-update
- ResourcePack/DataPack managed deployment
- resource-pack SHA/UUID automation
- SBOM/provenance/dependency/security scans
- reproducibility hardening
- shared artifact cache
- disaster-recovery drill
- Lobby implementation/fleet integration if Day-10 design is approved

## 완료 기준

이 시스템의 최종 완료 기준은 “업데이트가 자동으로 된다”가 아니라 다음입니다.

1. 잘못된 commit은 CI에서 차단된다.
2. 검증되지 않은 artifact는 stable에 들어가지 않는다.
3. 서버는 인터넷 장애 때문에 시작 실패하지 않는다.
4. 교체 중 전원이 꺼져도 이전 정상 상태를 복구할 수 있다.
5. 새 플러그인이 부팅을 깨면 자동 또는 한 번의 rollback으로 복구된다.
6. 어느 서버에 어느 버전이 설치됐는지 GSC/GSCM에서 즉시 알 수 있다.
7. 배포와 rollback 이력이 남는다.
8. 자체/외부 업데이트 정책이 분리된다.
9. Android/iOS 배포 제약을 플랫폼에 맞게 처리한다.
10. 운영자가 JAR을 직접 복사하는 작업을 거의 하지 않아도 된다.
