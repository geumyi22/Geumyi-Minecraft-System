# Day 12 P0 핵심 설정 복구 준비 — 2026-10-17

## 실측/사용자 확인과 상태

- 운영자의 클라우드 웹 화면에서 Google Drive **2TB 계정 / 사용량 약 3.74GB**, OneDrive **1TB 계정 / 사용량 약 441.4GB**를 확인했다. 운영자는 Windows `G:`가 그 Google 계정에 로그인된 가상 드라이브이고, 원본 서버는 **OneDrive에만 존재**하며 Google에는 서버 데이터나 독립 백업이 없다고 확인했다.
- 이 웹 계정 사용량은 개별 Minecraft 서버 크기가 아니며, 시점이 바뀔 수 있다. 정확한 bytes 여유량, DriveFS 로컬 캐시, 전송 대기, 파일 당 크기 제한, 장시간 업로드 상태는 별도 증거가 필요하다.
- Day12 capacity-v1의 OneDrive 서버 4곳 `0 bytes`는 해당 폴더의 cloud/reparse 객체를 안전을 위해 제외한 **불완전한 관측**이다. GSC 상태 경로에 관측된 데이터는 서버 월드·플러그인 전체 크기의 대체 지표가 아니다.
- **복구용 독립 Google 아카이브는 아직 없음. P0 데이터 읽기/암호화/Google 업로드/Google 재다운로드/격리 복원 0건.**

## 소스 검토에 기초한 P0 후보

| 범위 | 1차 후보 | 비밀/정합성 주의 |
|---|---|---|
| GSC Host | `%ProgramData%\GeumyiServerCenter\server.json` | `api_token`, `agent_api_token`, `github_token`, 페어링·기기 연결 정보 등이 있을 수 있음. 평문을 채팅/GitHub/G:에 올리지 말 것 |
| Wild / Playground / Other / Lobby | 실제 GSC config/API에서 정합 일치한 **각 서버 루트**의 `server.properties` | `rcon.password` 등 민감정보 가능. Other는 OFFLINE 유지 |
| 각 Paper | `bukkit.yml`, `spigot.yml`, `permissions.yml`, `ops.json`, `whitelist.json`, `banned-players.json`, `banned-ips.json`, `config/paper-global.yml`, `config/paper-world-defaults.yml`, `start.bat`/`start.cmd`, `eula.txt` | 존재/필요 여부는 환경 의존. 개별 파일을 발견해도 플러그인 데이터/월드 백업이 아님 |
| Wild / Other 일부 기술 플러그인 | `plugins/GeumyiTechnology/config.yml`, `plugins/GeumyiChemistry/config.yml` | 설정 파일만. 플러그인이 별도로 저장하는 머신/플레이어 상태는 P1 정합성 범위 |
| 3개 Velocity 인스턴스 | 각 실행 루트의 `velocity.toml`, `forwarding.secret` 및 Geyser/Floodgate 설정·키 | **실경로 미확인**. 세 프록시와 서버 간 동일한 forwarding secret 관계를 복구 시 입증해야 하므로 자동 추정 금지 |
| GSC 모바일/공통 런타임 | 기기 페어링, GSCM 연결, StatusAgent 토큰, GDS/로비 서버 연결, 배포 바이너리 버전·서명 | `server.json`만으로 전부 복구된다고 보장할 수 없음. 별도 원본/상태·권한 보존 매핑이 필요 |

**금지:** 기존 GSC 백업 API의 `config`/ZIP 기능을 곧바로 P0 암호화 백업으로 간주하지 않는다. 원래 ZIP은 평문이고 내부 manifest에 절대 경로가 들어갈 수 있다. 공개 저장소 템플릿은 실제 운영 자격증명·로컬 상태 백업을 대체하지 않는다.

## 이번에 추가한 스코프 한정 도구

`tools/day12/cloud/Day12_P0_Config_Presence_READ_ONLY.ps1`는 v4/v5에서 이미 검증된 경로 resolver를 **읽기 전용**으로 가져와, 4개 Paper/GSC의 **고정된 이름만** 메타데이터 조회한다. 재귀 디렉터리 열거·P0 후보 파일 본문 오픈·비밀값 출력·서버/클라우드 수정이 없고, nested reparse 하위 조회를 거부한다.

- OneDrive 루트 자체는 이미 알려진 reparse 경로지만, 내부 파일이 cloud/reparse/offline/recall-on-access인 경우 `CLOUD_OR_REPARSE_CONTENT_NOT_INSPECTED`로 분류하고 내용은 읽지 않는다.
- **예외 범위:** 기존 GSC 서버 경로 resolver는 `server.json` 설정 텍스트와 경로 포인터 파일을 로컬 메모리에서 실제로 읽는다. 그러므로 전체 실행에서 파일 내용을 전혀 읽지 않는다는 주장은 하지 않는다. 후보 파일은 메타데이터 조회만 수행한다.
- 정확한 파일 경로는 private in-memory 처리. 공유 JSON에는 각 항목의 상대 이름·계급·민감 여부·메타데이터 분류만 기록한다.
- 서버가 온라인 상태여도 중지/저장/스냅샷을 수행하지 않음. 데이터 정합성 또는 복구 가능성에 관한 결론 없음.
- 세 Velocity 원본 경로는 이 도구로 발견했다고 주장하지 않으며 `THREE_VELOCITY_PROXY_ROOTS_AND_SECRETS_NOT_INVENTORIED` 차단 근거를 항상 남긴다.
- metadata access가 cloud client의 메타데이터 갱신을 일으킬 수 있으므로, 현장 관찰과 클라우드 상태에 따라 중단 가능. placeholder hydration 없음이 OS/클라이언트 수준에서 독립 입증된 것은 아님.
- 실행 가능한 P0 백업·암호화·업로드·복원 허가 플래그는 모두 false이며, 단순 존재 검사 통과로 변경 불가.

## 안전한 향후 P0 실행 게이트 (아직 미충족)

1. 실제 GSC·4 Paper·3 Velocity 및 Geyser/Floodgate/모바일 관련 공통 상태 위치를 비공개로 확정하고, 복원에 필요한 바이너리+설정 간 버전 관계를 기록.
2. 민감정보·키 재설정/별도 보관/암호화 설계 수립. 암호/키를 명령행 인수·공개 경로·대화에 입력하지 않는다. 복원자가 키를 확보할 수 있는 **독립 키 복구 절차** 검증.
3. OneDrive 서버 루트와 GSC 설정에 대한 소스 read/placeholder hydration 영향, 읽는 시점의 consistency, writer 상태 및 필수 권한 확인. 필요한 경우 운영자 명시적 승인 후 점검 시간 확보.
4. 개발/일회용 Windows 샌드박스에서 선정된 exact files의 zip/tar 경로 정규화, AEAD 암호화, 부분 아카이브 해시, 실패 시 원본/암호문 불변성, 임의경로 복원 차단을 별도 검증. 2026-10-15 합성 암호화 CI 성공을 생산 적용 성공으로 혼동하지 않기.
5. 실제 운영 원본으로 작업할 때는 명시적인 운영 승인과 독립 경로 검증, 로컬 스테이징 용량, Google 계정 연결 검증, 업로드 후 서버 측 존재/재다운로드/격리 복원 성공을 모두 증명해야 P0=COMPLETE 처리.
6. P0 이후에도 월드 및 별도 플러그인 상태 P1 확보 전에는 Stable/ACL/Canary production gate 변경 금지. Other 기동 금지.

이 문서는 복구 전략을 정의한다. **아직 백업 실행 승인이나 복구 증거가 아니다.**
