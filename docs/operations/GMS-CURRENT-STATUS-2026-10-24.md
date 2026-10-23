# Geumyi Minecraft System — 현재 상태 및 안전한 인수인계

> 기준: **2026-10-24 KST**, GitHub 공개 API 확인 + 이전 운영자 제공 실서버 결과. 이 문서는 **공개 가능한 요약본**이며, 개인/서버 설정 원본이나 완전한 시스템 백업이 아니다.
>
> **상태 구분**: `main`의 Stable 소스, GitHub에 공개된 수동 설치 패키지, Draft Canary 개발, 실제 Windows 서버 설치판, 엄격한 보안·자동배포 게이트는 **서로 다른 사실**이다.

## 1. 지금 읽어야 할 버전 기준

| 범위 | 최신 확인 사실 | 근거/제한 |
|---|---|---|
| 기본 브랜치 `main` | `0d765f9897066ee2388bca9e98a390f3b2d331a9` | 2026-10-24 GitHub 조회. 기존 버전 정리의 중심 |
| 최신 공개 수동 설치 Stable | **GSC 4.5.1 / GSCM 1.5.1+151** | [Stable release](https://github.com/geumyi22/Geumyi-Minecraft-System/releases/tag/system-2026.10.11-stable-gsc451-gscm151). 실제 설치 증명 아님 |
| 서명 Beta 업데이트 | GSC **4.5.1**, `deployment-beta.json` | [Signed Beta](https://github.com/geumyi22/Geumyi-Minecraft-System/releases/tag/system-2026.10.11-gsc451-signed-beta.1). Stable 자동승격 아님 |
| 개발 후보 | GSC **4.5.2 Canary**, Draft [PR #57](https://github.com/geumyi22/Geumyi-Minecraft-System/pull/57) | `feature/velocity-lifecycle-isolated-engine-20261017`, HEAD `cbc2e35a8b3f1c1dfc3483a3e1ca821fd4b769a3` |
| 마지막 정식 기기 통합 확인 | GSC **4.3.8**, GSCM **1.1.5+117** | Day 11/12 보고 당시. 새 공개 패키지 설치/앱 실기기 E2E와 구별 |
| 운영자의 후속 Canary Host 보고 | GSC **4.5.2 Canary Host** 설치/기동 성공 보고(2026-10-21) | 운영자가 `HOST_CANARY_ACTIVE_VERIFIED`를 제공. 2026-10-24 현재 서버를 직접 재조회한 것은 아님 |
| Velocity 직접 관리 전환 | **0/3** | Day10 Scheduler 방식 유지. GSC Host Canary 교체와 다름 |
| 엄격한 signed Stable 자동배포 | **차단 유지** | [FINAL-RELEASE-GATES.json](../../FINAL-RELEASE-GATES.json): `stable_release_allowed=false`, `maintenance_mode_allowed=false` |

GitHub에 Stable 이름의 **수동 설치** 릴리즈가 게시된 사실은 `deployment-stable.json` 자동 배포 또는 실서버 4.5.1/1.5.1 설치·E2E 성공을 뜻하지 않는다. iOS IPA는 **미서명**이므로 Apple 서명과 프로비저닝 없이는 설치할 수 없다.

## 2. Day 1~12 완료 이력과 이후 개발의 분리

| 범위 | 완료/보존할 역사 |
|---|---|
| Day 1~3 | 소스·버전·GSC/GSCM/GDS/GST/Agent 복구, CI 시작, 원본과 재구성 소스 구별 |
| Day 4~6 | Wild/Playground 실서버 E2E, 운영 안정화, Android/iOS 모바일 실기기 확인 |
| Day 7~9 | Go/Java/Flutter 자동 빌드, Ed25519 릴리즈 체계, backup→staging→atomic apply→health→rollback |
| Day 10 | Velocity 3개 + Geyser/Floodgate + 중앙 Lobby + Paper 4개 프로필의 라우팅, 재부팅 자동 시작, Java/Bedrock 접속 확인 |
| Day 11 | GSC 4.3.8 / GSCM 1.1.5+117, Host·Client 별도 업데이트, Fleet/Update Center, Protection & Recovery 2.0, final E2E |
| Day 12 | 2026-10-11 **소규모 운영 기준 마감**. 역사적 4/4 Golden protected backups, 84/84 known-good cache SHA, disposable DR CI 등. **엄격한 Stable 보안 게이트는 미승인** |
| **Day12 이후** | 2026-10-17~23의 GSC 4.5.2 Canary/Velocity 관리 개선은 **별도 유지보수 개발**이며 Day12 마감 이력을 뒤집거나 PR을 Stable로 바꾸지 않는다 |

원래 단계 번호의 유일한 기준은 [DAY-TIMELINE.md](../../DAY-TIMELINE.md). 당시 운영 범위의 종료 판단은 [PROJECT-CLOSEOUT-2026-10-11.md](../../PROJECT-CLOSEOUT-2026-10-11.md). 두 파일은 **역사적 기준 문서**이므로 나중의 Canary 유지보수 상태를 덮어쓰려고 재해석하지 않는다.

## 3. 프로그램과 서버 아키텍처

- **GSC**: Go 기반 Windows Host 서비스/Client 분리; Paper 서버 수명주기·상태·콘솔·백업·업데이트·롤백. `GSC/ServerCenter/`.
- **GSCM**: Flutter Android/iOS, 보호된 페어링·HTTP/WebSocket·원격 상태/제어·업데이트 확인. `GSCM/`.
- **GDS**: Geumyi Discord Status 플러그인 **1.1.1**. `Plugins/GeumyiDiscordStatus/`. GSCM과 다른 컴포넌트.
- **GST**: Geumyi Server Tools **1.1.1 HOTFIX**. 원본 0.1.5 core 일부는 바이너리 기반, overlay 복구 근거 유지.
- **StatusAgent**: **0.5.4**. `GSC/StatusAgent/`.
- **GeumyiNetwork 0.1.0**, **GeumyiLobby 0.1.0**, **Technology 0.1.4**, **Chemistry 0.4.1**: Paper 플러그인. 소스 복구/버전·실서버 검증 수준은 각 README와 [recovery report](../reference/RECOVERY-REPORT.md)에서 확인.
- **메인 서버컴**: Windows GSC Host, Paper, 기존 Day10 Velocity×3/Geyser/Floodgate, Windows 서비스·스케줄러. **원격 관리 PC(서브컴)**는 GSC Client를 별도 실행/업데이트. Host와 Client 버전을 하나라고 가정 금지.
- **기타(Other) Paper 게임 서버는 가장 최근 운영자 확인에서 의도적으로 OFF**. 기타 Velocity Scheduler task가 Running이거나 Geyser 포트가 점유돼도 Paper ON으로 추론 금지.
- 일반 원칙: 공개 Java/Bedrock 입구는 Velocity 3개, 중앙 Lobby 후 backend로 이동. Paper backend/RCON은 비공개 바인드 의도. 실제 native owner/bind 보안 게이트는 아직 PASS가 아니다. 네트워크/포트의 보존된 스냅샷은 [FINAL-NETWORK-TOPOLOGY.json](../../FINAL-NETWORK-TOPOLOGY.json)을 참조하되 최신 Windows/방화벽 실측이라고 간주하지 않는다.

**원본 World, 서버 설정, credentials, ACL, Scheduled Task XML 및 보호된 Golden 백업은 GitHub에 올리지 않는다.** 운영자 관리 백업 자산은 원래 서버의 보호된 위치에 남아 있으며 이 문서/저장소에 포함돼 있지 않다.

## 4. 2026-10-17~23 Velocity Canary 유지보수 현황

### 이미 확인된 것

1. Windows Scheduler의 고정 Day10 Velocity task 3개가 이전 검사에서 `Running`; `RestartOnFailure=999`. 실제 각 작업→JVM 핸들/stdin의 GSC 소유권은 **증명되지 않음**.
2. 사용자 제공 read-only 진단에서 Velocity JAR 부모/자식 JVM 관련성, Geyser UDP 각 프로세스/예상 작업 디렉터리, Velocity 설정의 예상 공개 포트가 확인됐다. 독립적인 작업 스케줄러 task 인스턴스 identity와 현재 Java TCP LISTEN 상태는 여전히 논점.
3. TCP LISTEN=0 검사와 달리, 사용자 Java 클라이언트의 야생 실제 로그인은 성공했고, 접속 중 원격 **25565** 및 Velocity 루프백→야생 Paper **25570** 연결이 관찰됐다. 각 소켓의 완전한 동일 세션 대응이나 현재 listener owner 보안 게이트를 PASS로 결론내릴 수 없다.
4. [PR #57 전환 구현](https://github.com/geumyi22/Geumyi-Minecraft-System/blob/feature/velocity-lifecycle-isolated-engine-20261017/docs/operations/GSC-VELOCITY-DIRECT-OWNERSHIP-CUTOVER-2026-10-19.md): GSC가 직접 시작한 Java 자식의 stdin/handle로 `shutdown\n` 후 종료 확인, 중복 시작 방지, 검증된 task XML/launch manifest·receipt·독점 owner marker를 전제로 한다. 기존 외부 Scheduler 프로세스를 임의 PID로 강제 종료하거나 그대로 인수하지 않는다.
5. PR #57의 마지막 CI에서는 전환 사전검사의 **passive TCP/UDP 조회**, 포트 점유 시 FAIL-CLOSED, 격리 Windows 환경의 snapshot→disable→rollback 및 공식 Velocity graceful shutdown/restart가 통과했다. **CI 결과는 실서버 마이그레이션 증명이 아니다.**
6. 실제 사용자 승인/Canary Host 활성 보고가 있었더라도 세 프록시의 GSC 직접 시작·종료 소유 전환은 **0/3**. Windows task 원본/복구본은 보존해야 하고, 실서버 대량 JVM 종료나 3개 동시 전환은 안 된다.

### 남은 필수 검증

- 실행 중인 Scheduler 소유 JVM의 **확실한 종료·자식 프로세스 정리와 자동 재시작 억제**, 관련 포트 해제 확인.
- 기존 보호된 로컬 snapshot/manifest/ticket 검증; **중복 스냅샷 생성 금지**.
- 한 프록시씩 원래 task를 안전하게 비활성화한 뒤 GSC 소유 JVM 시작·중지·재시작 확인, Java+Bedrock 클라이언트 E2E, Host 재시작/orphan 처리, rollback.
- 다른 프록시 및 Paper worlds/Golden backups 불변성 증명.
- 정확한 절차/현재 후보 코드는 **Draft PR #57**의 운영 문서와 `tools/velocity/`에서만 추적; 아직 메인 배포판에 포함되지 않았다.

## 5. GitHub PR·브랜치 정리 현황(삭제/병합 아님)

2026-10-24 확인 시 **19개 브랜치, 10개 열린 PR**가 있다. 2026-10-11에 5개로 축소됐다는 [과거 closeout 기록](../../PROJECT-CLOSEOUT-2026-10-11.md)은 당시 스냅샷이며 지금 숫자가 아니다.

| 구분 | 열린 PR | 현재 분류 |
|---|---|---|
| Day12 보안과 통합 | [#47](https://github.com/geumyi22/Geumyi-Minecraft-System/pull/47), [#48](https://github.com/geumyi22/Geumyi-Minecraft-System/pull/48), [#49](https://github.com/geumyi22/Geumyi-Minecraft-System/pull/49), [#50](https://github.com/geumyi22/Geumyi-Minecraft-System/pull/50), [#52](https://github.com/geumyi22/Geumyi-Minecraft-System/pull/52), [#53](https://github.com/geumyi22/Geumyi-Minecraft-System/pull/53) | **Draft/CI/보안 리뷰 범위**. 상호 의존·중복 여부 판단 전 삭제·대량 merge 금지 |
| 릴리즈 채널 정책 | [#54](https://github.com/geumyi22/Geumyi-Minecraft-System/pull/54) | Draft, 정책/UX 리뷰 후보. 구현 완료·배포로 표시 금지 |
| Velocity 상태만 조회 | [#55](https://github.com/geumyi22/Geumyi-Minecraft-System/pull/55) | Draft, read-only. PR #57과 겹치는 범위 점검 필요 |
| Velocity 직접 관리 | [#57](https://github.com/geumyi22/Geumyi-Minecraft-System/pull/57) | **주 개발 기준**, Canary/코드/CI PASS, live cutover 0/3. `main` 병합 보류 |
| Velocity 플러그인 실험 | [#58](https://github.com/geumyi22/Geumyi-Minecraft-System/pull/58) | Draft, status-only/비제어 대안. PR #57의 직접 제어와 혼동 금지 |

**정리 원칙**: 참조 SHA와 PR 의존성을 먼저 확인하고, 일회성 도구와 완료 PR의 이력을 보존한다. 코드가 다른 브랜치에 병합됐다는 확인이 없는 PR/브랜치를 오래됐다는 이유만으로 닫거나 삭제하지 않는다. CI와 Actions artifacts는 영구 보존이 보장되지 않는다.

## 6. 최신 공개 Actions 확인(브랜치 SHA 연결)

다음 4개 작업은 `feature/velocity-lifecycle-isolated-engine-20261017`의 **`cbc2e35a8b3f...`**에서 `SUCCESS`로 확인됐다.

- [System CI #39825360829](https://github.com/geumyi22/Geumyi-Minecraft-System/actions/runs/39825360829)
- [Day 11 Host Test #39825360865](https://github.com/geumyi22/Geumyi-Minecraft-System/actions/runs/39825360865)
- [Day 12 Synthetic DR #39825360823](https://github.com/geumyi22/Geumyi-Minecraft-System/actions/runs/39825360823)
- [Day 12 Security SBOM/Reproducibility #39825360800](https://github.com/geumyi22/Geumyi-Minecraft-System/actions/runs/39825360800)

과거 실행의 failed/cancelled 이력도 남는다. 위 확인은 **이 특정 SHA에서의 CI PASS**일 뿐, 실제 서버/모바일 앱 E2E·공식 Stable 배포·현재 설치 성공 증명이 아니다.

## 7. 백업과 인수인계 보존 범위

- Golden **4/4**, known-good cache **84/84**는 기존 운영자 증빙/역사적 Day12 완료 기록. 2026-10-24의 새 해시 재검사는 수행하지 않았다.
- 로컬 Protected Backup, Scheduled Task XML/receipt, ProgramData ACL, 운영 secrets, 월드, 기기 앱 데이터의 **실물은 GitHub에 보존하지 않음**. public GitHub 파일만으로 disaster recovery는 불가능하다.
- 전체 개인용 MASTER HANDOFF(2026-10-24)와 보존 ZIP은 **이 저장소 밖**의 사용자 보관 자료이다. 그 파일을 공개 GitHub에 자동 업로드하거나 public repo에 개인/운영 데이터가 섞이게 하지 않는다.
- 기존 Windows **Unified Release Manager v3.0.2 Hotfix PowerShell/CMD**는 별도 사용자 보관 ZIP에 존재. 이 저장소에 내장된 릴리즈 스크립트가 아니므로 새 스크립트나 설치 성공을 임의로 주장하지 않는다. GitHub 출시 전에 기존 도구의 Windows 실기기/권한/태그 정책을 별도로 확인.
- `main`의 버전 기준/이력: [README](../../README.md), [DAY-TIMELINE](../../DAY-TIMELINE.md), [VERSION-MATRIX](../../VERSION-MATRIX.md), [CLOSEOUT](../../PROJECT-CLOSEOUT-2026-10-11.md), [FINAL RELEASE GATES](../../FINAL-RELEASE-GATES.json), [docs index](../README.md).
- `main` 소스는 현재 PR #57의 Canary 기능을 내장한 것으로 취급하지 않는다. 복구를 위해 증빙 원본을 무조건 overwrite/cleanup/force-push하지 않는다.

## 8. 다음 단계 (이번 GitHub 정리에서는 수행하지 않음)

1. **P0:** 개인 보존 MASTER HANDOFF+ZIP의 접근성·원본과 실제 World/Golden/Task snapshot 분리 보관 확인.
2. **P1:** 운영자 요청이 있을 때 서버/서브컴의 현재 설치판과 실제 Velocity task/JVM 상태에 대한 한 번의 정확한 read-only 재확인.
3. **P1:** PR #57의 안전한 legacy task 종료·GSC 직접 제어/역전환 절차를 별도 승인·실운영 제한 하에 구현 및 검증.
4. **P2:** 12.5/12.10/12.11/12.12/12.13 보안/soak 증빙 보완. `FINAL-RELEASE-GATES.json`의 FAIL을 근거 없이 PASS로 바꾸지 않는다.
5. **P2:** Unified Release Manager v3.0.2의 Windows PowerShell 5.1·GitHub auth·Dry-run 재검증. 실제 Release 생성 및 Stable 승격은 별도 승인.
6. **P3:** open PR 간 중복/의존성과 브랜치·CI artifacts의 보존 정책부터 검토한 뒤에만 별도 정리.

**이번 GitHub 문서 정리의 한계**: docs 브랜치의 상태 인수인계 업데이트만 포함한다. 서버 PC 작업, 실행 파일·플러그인 코드 변경, release/tag 삭제·발행, `main` 강제 병합, private 백업 업로드는 수행하지 않는다.
