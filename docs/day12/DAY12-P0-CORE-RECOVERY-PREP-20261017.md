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
| 3개 Velocity 인스턴스 | 각 실행 루트의 `velocity.toml`, `forwarding.secret` 및 Geyser/Floodgate 설정·키 | **세 프록시 경로·설정 및 비밀키 존재와 로컬 SHA-256 일치는 운영자 관측 완료**. 키 유출 없이 별도 복원 가능성 확인이 여전히 필요 |
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

## 2026-10-17 실제 P0 설정 메타데이터 검사

- 운영자가 제공한 `DAY12-P0-PRESENCE-V1-SHARE-ONLY-THIS.json`은 `P0_PRESENCE_REVIEW_REQUIRED` 및 `read_only=true`이고 네 Paper 루트와 GSC 상태 루트의 메타데이터 접근이 관측되었다. JSON에 비밀번호/절대 경로는 기록되지 않았다고 보고된다.
- Wild/Playground/Other/Lobby의 **각** `server.properties`에 `CLOUD_OR_REPARSE_CONTENT_NOT_INSPECTED`가 기록되었다. OneDrive의 cloud/reparse 파일 메타데이터를 관측했을 뿐, 본문·해시·열람/복원 가능성 또는 네 원본의 시점 일관성을 확인한 증거가 아니다.
- GSC `server.json`은 `LOCAL_FILE_METADATA_OBSERVED`. 이 1개로 모든 GSC runtime/token/pairing 상태와 백업 스냅샷이 완성됐다는 의미는 아니다.
- Wild/Playground/Other의 `permissions.yml`과 각 서버의 `start.cmd`는 `FILE_NOT_PRESENT` 범주로 관측되었다. 선택적 후보의 부재일 뿐, 기존 `start.bat` 관측이 있으므로 오류로 격상하지 않는다. Lobby의 `permissions.yml`은 cloud/reparse 범주로 관측됐다.
- Paper `config/` 및 Wild/Other 기술 플러그인 설정 하위 후보는 `NESTED_REPARSE_OR_CLOUD_PARENT_BLOCKED`. 파일 누락 증거가 아니며 검사를 반복하거나 재분석 지점을 강제로 따라가지 않는다.
- 재사용 가능한 이전 근거: `tools/day10/finish_four_servers.ps1`는 세 Velocity의 설치 위치를 `%PROGRAMDATA%\\GeumyiServerCenter\\Network\\FourServer\\{wild,playground,other}`로 생성하고 `Geumyi Day10 Velocity {id}` 예약 작업의 `WorkingDirectory`에 연결한다. 이전 2026-10-10 Bedrock inventory 정정 후 `root_present=true`가 관측되었다. **이는 현재 운영자 PC의 새 경로 검사 결과가 아니며, 현재 파일 내용/키 일치성도 미검증**이다. 무의미하게 이전 Day10 프로세스/네트워크 테스트를 반복하지 않는다.
- **남은 P0 핵심 갭:** 세 Proxy의 실경로·설정·키 존재/로컬 일치 관측은 완료됐으나 **실제 설정 내용 무결성·파일 간 시점 일치·독립 키 회수·격리 복구 미검증**. 추가적으로 GSC/GDS/StatusAgent 모바일 관련 credential/state와 정확한 복원 순서 확인 필요. 실제 민감정보 파일은 채팅/공개 GitHub에 올리지 않는다.
- 운영 클라우드: 실제 원본 OneDrive, Google Drive G:는 로그인만 된 별도 2TB 계정, 원격 웹 저장량은 운영자 화면으로 확인. Google Drive에 복구 아카이브를 생성했다고 주장하지 않는다.
- 신규 조사 수집보다 원본/메타데이터 재사용을 우선한다. 실제 백업 전에는 안전한 비공개 로컬 AEAD 키 입력, 소스 read/Files On-Demand 영향, 원본 스냅샷 정합성, 소스와 출력의 물리적 분리, 클라우드 실제 업로드/다운로드/격리 복원의 증거가 필요하다. P0/P1/Stable 게이트 계속 false.

## 2026-10-17 이어진 실호스트 Velocity 실행·키 일치성 관측

운영자가 서버 PC에서 정확히 출력된 표를 공유했으며 **비밀 원문·키 해시·실경로는 공유하지 않았음**.

- `wild`, `playground`, `other` 각각에 대해 설치 폴더·`velocity.toml`·`forwarding.secret`·Geyser 설정·Floodgate 설정 **5/5 True**. 이는 파일 존재 판정이지 키 열람/백업 증명이 아님.
- 세 역할의 `Geumyi Day10 Velocity {role}` 예약 작업이 모두 **Running**, 각 실행 디렉터리와 Day10 원본 배포 기준 일치(`PathMatch=True`). `velocity.jar`, `plugins/Geyser-Velocity.jar`, `plugins/floodgate-velocity.jar`, `plugins/floodgate/key.pem`도 각 3/3 True. **Other Proxy Running은 Other Paper ONLINE을 의미하지 않음**.
- 운영자 로컬 PowerShell은 3개의 `forwarding.secret` 파일 SHA-256 동일 여부만 `True`로, 3개의 `floodgate/key.pem` SHA-256 동일 여부만 `True`로 보고. 실제 바이트·해시는 전송되지 않았고 key recovery/restore 유효성까지 검증된 것은 아니다.
- 해당 검사에서 `Get-FileHash`는 각 키 파일을 실제 읽어 SHA-256을 구하므로, OneDrive placeholder가 아니라 ProgramData 로컬 경로에만 한정됐다는 실행 스코프가 중요함. 이 상태를 백업 암호화 키 저장 경로와 혼동하지 않는다.
- **중복 검사 금지:** 위 3개 프록시 경로/예약작업/비밀키 SHA 동등성 검사를 반복 요청하지 않는다. 새 버전·파일 변경/운영 장애가 발생할 때만 증거 갱신.

## P0 암호화 계약: 합성 검증과 생산 경계 분리

- `tools/day12/cloud/p0_crypto_contract_disposable.go`는 기존 `disposable_crypto_roundtrip.go`와 결합해 **정해진 P0 상대경로만 허용하고 반드시 4개 Paper + 3개 Velocity 설정·전달키·Floodgate 키 + GSC 설정이 포함된다는 합성 계약을 테스트**한다. 월드/임의 경로·누락/불일치 키를 거부한다.
- 가짜 암호와 구성 파일만 TAR→분할 AES-256-GCM→HMAC manifest→별도 격리 폴더에 복구한다. 누락·변조·잘못된 키·경로 이탈·심볼릭 링크 거부 테스트는 이전 합성기에서 재실행한다. 실제 키를 읽거나 출력하지 않는다.
- **이 파일은 실제 백업 프로그램이 아니며, 테스트 성공으로 GSC·Paper 운영 비밀키의 복원/클라우드 업로드가 성공했다고 주장하지 않는다.** 실제 원본 접근 없이 CLI 실행을 허용하는 운영 프로그램이 아직 없음.
- 실제 운영용 P0 암호화 도구를 승인하려면 (1) 사용자 데이터/키를 프로세스 인수나 공개 로그에 내놓지 않는 256비트 키 생성 및 독립 회수 수단, (2) Source OneDrive hydration/read consent, (3) 파일별 원본/재분석/용량 상한, (4) GSC/프록시/플러그인 writer 일관성, (5) 출력-원본 물리 분리와 no-overwrite, (6) 암호문 무결성·Google Drive 업로드 완료·독립 다운로드·격리 복원, (7) Windows 실제 실행 검증이 필요하다.
- GitHub PR #53은 Draft. 현재 `p0_backup_allowed=false`, `stable_release_allowed=false`; 절대 자동 변경하지 않는다.

## Windows/Linux P0 합성 암호화 CI 결과

- [검증 실행 #38940950883](https://github.com/geumyi22/Geumyi-Minecraft-System/actions/runs/38940950883): **Windows-latest SUCCESS, Ubuntu-latest SUCCESS**. P0 필수 상대경로, 가짜 Velocity/Floodgate 키 동등성, 가짜 GSC·Paper 설정, AES-256-GCM/HMAC, 격리 복원, 경로 이동/심볼릭 링크·변조 거부를 합성 데이터로 실행.
- 이 **2/2 PASS**는 코드 테스트 한정이다. 실제 Windows 실서버 OneDrive, Google G: 업로드, 운영자 키 보관, 원본 source/hydration 영향, 정합 스냅샷, 원격 다운로드 복구 또는 P0 게이트 완료는 모두 미검증.
- 실제 백업 수행과 최종 release 허가는 기존대로 BLOCKED. 원본 서버/프로세스/키/클라우드 데이터 변경 없음.

## 2026-10-17 운영자의 P0 설정 파일 선택 읽기 승인

운영자가 P0 백업을 위해 **선별된 서버 설정 파일만 읽고, OneDrive Files On-Demand로 인한 해당 파일의 로컬 다운로드가 필요한 경우 이를 허용**했다. 이는 원본 변경·동기화 정책 변경·월드 전체 데이터 읽기·Google Drive 업로드·서버 정지/재시작·Stable 릴리스 승인으로 확대되지 않는다.

### v1 로컬 암호화 캡처 설계 (명시적 승인 내 최소 범위)

- 정확히 20개: GSC `server.json` 1, Paper `server.properties` 4, Velocity 각 `velocity.toml`, `forwarding.secret`, Geyser 설정, Floodgate 설정과 `key.pem` 5종 × 3.
- Day10 예약 작업과 기존 v4/v5 GSC+API source mapping를 재사용한다. 모든 Paper 원본은 운영자가 확인한 OneDrive 루트 내부여야 하고, 모든 백업 생성은 **별도의 신규 LOCALAPPDATA/GMS staging** 아래에서만 허용된다. 소스/공급자 겹침 혹은 alias 근거 불확실 시 실패.
- 암호는 `Read-Host -AsSecureString`으로 새 복구용 passphrase를 2회 수집하고, UTF-8 JSON을 **콘솔 파이프(표준입력)** 로 암호화 Go 실행 파일에 전달한다. 프로세스 인수, 파일 내 고정 암호나 공개 보고서에 기밀을 전달하지 않는다. 최소 20문자·PBKDF2-HMAC-SHA256 450,000회·랜덤 salt·AES-256-GCM, 각 파일 인증 AAD는 아카이브 ID/순번/상대경로를 묶는다. 분할 암호문과 암호화된 manifest만 로컬 출력한다.
- 키 손실 시 복구가 불가능할 수 있으므로 별도 오프라인 보관을 운영자에게 요구한다. 별도 PC의 독립 복호화·실제 복원 도구가 아직 없으므로 생성 직후 로컬 복호/해시 일치만으로 **독립 키 복구 PASS를 주장하지 않는다**.
- 원본 파일마다 단일 8MiB / 총 48MiB 캡, 읽기 전후 크기·수정 시각 점검 및 캡처 시 세 프록시 실키 바이트 동일성 재확인; 읽기 중 변조/누락/키 불일치 시 incomplete. 이것은 원자적 멀티서비스 snapshot 보증이 아니다.
- Google G:에는 절대 자동 쓰지 않음. 클라우드 전송은 암호화 출력이 확인된 후 독립 단계에서 수행할 별도 승인 사항이다.
- 기존 synthetic fixture `tools/day12/cloud/p0_crypto_contract_disposable.go`는 그 자체로 생산용 백업 도구가 아니다. 신규 `p0_local_encrypted_capture.go`는 자기 완결형 가짜 파일 합성 캡처 테스트에 성공한 경우에만 Windows 실행 파일을 CI 아티팩트로 패키징한다.
- 실제 운영자 실행·백업 성공·Google 업로드·독립 복원·P0 게이트 완료는 **아직 미실행/미검증**. CI 실패 시 실패본을 운영자에 배포하지 않는다.
