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

## P0 로컬 암호화 도구 v1 — 합성 CI 완료, 운영 실행 대기

- [GitHub Actions #38943566555](https://github.com/geumyi22/Geumyi-Minecraft-System/actions/runs/38943566555): **Windows 합성 테스트 SUCCESS, Ubuntu 합성 테스트 SUCCESS, Windows operator ZIP 패키징 SUCCESS**.
- 파일 `Geumyi-Day12-P0-LOCAL-ENCRYPTED-v1.zip` SHA-256 `ab05119ba9a2374f93e7e185745fac58ee76d4f16a5e3ba6800957eb4a5a039d`, 1,126,449바이트. 실제 GitHub Actions 아티팩트 ZIP을 펼쳐 안쪽 ZIP의 정확한 7개 파일과 `BUILD-INFO-P0-LOCAL.json`의 SHA-256 목록을 검증했다. 해당 빌드 입력 HEAD `6e31b68ec2d3152c444a6330a2930ebac92f9c85`.
- 사용자 로컬에서 실제 실행된 것은 아님. **원본 OneDrive 설정 read/hydration, 비공개 로컬 암호화 캡처, 재다운로드, 독립 복원은 아직 0건.** 인증정보나 키를 GitHub에 업로드하지 않았음.
- 파일 내용이 바뀌거나 클라우드 placeholder/경로/쓰기권한 조건에서 벗어나면 fail closed. 그 경우 무리하게 재실행하지 않고 사용자 로그의 whitelisted 상태 코드만 확인한다. 20개 파일을 넘겨 P1 월드 데이터로 확대하지 않는다.
- P0 로컬 캡처 성공 시에도 **P0 복구 완료/Google cloud 독립 사본/어플리케이션 정합성/실서비스 복원/Stable**은 모두 미완료로 유지한다.

## 2026-10-17 운영자 P0 로컬 암호문 관측 — 범위 제한

운영자가 GUI/CMD 창을 먼저 닫아 성공 문구를 직접 보지 못했으나, 이후 제공한 **로컬 read-only 폴더 조사 결과**는 다음과 같다.

- \`Result=LOCAL_CAPTURE_COMPLETED\`, \`EncryptedParts=20\`, \`CompletionMarker=True\`, \`HeaderPresent=True\`, \`ManifestPresent=True\`.
- 해당 결과는 **P0 로컬 암호화 캡처의 완료 표시 및 20개 암호문 존재를 확인한 것**이다. 원본 파일·암호·개인 경로·암호문 자체는 채팅이나 GitHub에 수집하지 않았다.
- 성공 마커가 신뢰 가능한 생산용 암호화 도구에서 작성된 상태라면 생성 당시 자체 \`verify()\` 수행을 뒷받침하지만, 운영자가 실행 창을 닫아 당시 내부 검증 로그가 보존되었다고 주장할 수 없다.
- 이 폴더 존재 확인만으로 **독립 복원·Google Drive 업로드/다운로드·원자적인 멀티서비스 설정 시점·GSC/Paper/Velocity 서비스 기동 복원**이 통과한 것은 아니다. P0 독립 백업과 전체 Stable 게이트는 **BLOCKED**.
- 운영자는 같은 백업을 재생성하거나 원본을 다시 읽을 필요가 없다. 원본 암호화 폴더/복구 암호는 보존한다.

## 암호문 독립 재검증 설계

- \`p0_offline_archive_verify.go\`는 원본 캡처 작성기와 분리한 독립 검증기다. 기존 \`LOCALAPPDATA\\Geumyi-P0-Encrypted-Staging\\P0-...\` 완료 폴더에서만 헤더·암호화 매니페스트·20개 AES-256-GCM 파일을 읽는다.
- 같은 복구 암호를 로컬 \`Read-Host -AsSecureString\`으로 받으며, 암호 원문/소스 경로/원문 해시는 stdout·파일·프로세스 인수·GitHub에 쓰지 않는다.
- 파일별 AAD(아카이브 ID/순번/상대경로), AEAD 인증태그, 크기, SHA256, 20개 파일의 정확한 내용 이름/순서와 Proxy의 forwarding/Floodgate 두 키 그룹 동등성을 **메모리에서 복호화해 검증**한다. 복호화 평문을 디스크에 추출하지 않는다.
- 누락·추가·변조·잘못된 암호·정해진 staging 밖 접근은 실패. 검증 중 기존 암호문 파일 변경/새 백업 생성/온라인 서비스 재시작/클라우드 송신이 없어야 한다.
- 새 \`Test_P0_Offline_Verify_Interop_CI.ps1\`는 GitHub Windows/Linux 일회용 가짜 설정 데이터를 생산용 캡처기 포맷으로 암호화한 뒤 **서로 분리된 검증기**로 다시 읽는다. 실패 시 CI는 배포 ZIP을 생성하지 않는다.
- 이 검사는 암호화 archive **독립 디코딩 가능성(메모리 복원)** 범위 한정이며, 실제 격리 파일 추출, 서비스 구성 적용·기동 검증, Google 업로드/다운로드는 **다음 작업**이다.

## 2026-10-17 P0 로컬 백업 독립 AEAD 검증 도구 v1

- [Windows + Linux 테스트 및 패키징 CI #38953201117](https://github.com/geumyi22/Geumyi-Minecraft-System/actions/runs/38953201117): Windows·Linux 가짜 암호문 생성/독립 검증 상호운용 2/2 SUCCESS, Windows PowerShell 문법 검사 및 오퍼레이터 ZIP 패키징 SUCCESS.
- 사용자용 ZIP: Geumyi-Day12-P0-OFFLINE-VERIFY-READ-ONLY-v1.zip, 1,061,126 bytes, SHA256 66d5d90e7d7700c05a9fc0eca414e1087c4c8d35589817fcf6a130ebff2b84ff. 내부 다섯 파일의 빌드 정보/SHA256 목록 독립 대조 PASS.
- 실행: RUN_Day12_P0_Offline_Verify_READ_ONLY.cmd. 오직 LOCALAPPDATA의 가장 최근 완료된 P0 암호화 로컬 폴더만 읽는다. 새로운 암호화 백업·평문 복원 파일·클라우드 업로드는 생성하지 않고, 암호는 서버 PC에서만 입력한다.
- 별도 검증기 p0_offline_archive_verify.go는 정확히 20개 AES-GCM 파일, 암호화 매니페스트, 파일 상대경로/순서/AAD, 원문 길이·SHA256, 세 프록시 forwarding/Floodgate 키 동등성을 메모리 복호화해 재검증한다. 잘못된 암호·변조·누락·초과 항목을 거부한다.
- 이 문서는 CI SUCCESS와 운영자 보고 LOCAL_CAPTURE_COMPLETED까지만 입증한다. 운영자 실서버의 P0_OFFLINE_VERIFY_PASS 아직 미제공; Google Drive 실제 업로드·다운로드, 디스크로 격리 추출, 서비스 기동 복원, 전체 P0/P1/Stable 게이트는 계속 미완료.
- 사용자에게 원본 OneDrive 설정 재읽기·재백업 생성·복구 암호 공유를 요청하지 않는다. 이 새 암호문 독립 로컬 검증 결과를 받은 다음 Google Drive 암호문 안전 전송/독립 다운로드 검증을 진행한다.

## 2026-10-17 운영자 실제 P0 암호문 독립 메모리 복원 검증 결과

- **운영자가 실제 서버 PC에서 `RUN_Day12_P0_Offline_Verify_READ_ONLY.cmd`를 실행하여 `P0_OFFLINE_VERIFY_PASS`를 제공했다.**
- 출력 `P0_ENCRYPTED_FILES_VERIFIED=20`, `P0_NO_PLAINTEXT_OUTPUT=true`, `P0_REMOTE_CLOUD_DOWNLOAD_VERIFIED=false`, `P0_LIVE_APPLICATION_RESTORE_VERIFIED=false`. 실행기 출력에 `[PASS] Local AES-GCM authentication verified.`가 표시됨.
- 운영자가 기존 로컬 암호화 복구 암호를 서버 PC의 숨김 입력에서 제공했으며, 원문 비밀키·복구 암호·로컬 경로·암호문 또는 복호화 평문은 채팅/GitHub에 공유하지 않았다.
- **현장 P0 로컬 독립 무결성·메모리 복호화 검사는 PASS**로 기록하고 같은 기존 백업에 대한 재검사를 요구하지 않는다.
- 다만 이 결과는 백업 파일을 평문 파일로 추출한 격리 복구나 서버 서비스를 재기동하는 E2E 복구를 증명하지 않는다. Google Drive 업로드/원격 존재·독립 다운로드·복원은 **아직 0회**. 멀티서비스 설정 snapshot 원자성과 월드/플러그인 풀 백업 P1도 미완료.
- 다음 안전 단계는 **암호화 사본의 Google Drive 전송 전 별도 source/destination 읽기 전용 사전검사**와 전송에 대한 명시 승인 확인이다. 원본 OneDrive/server, 기존 암호화 백업, Other Paper 상태를 변경하지 않는다. G: mounted client checksum equal은 독립 클라우드 다운로드 E2E를 대체하지 않는다.

## 2026-10-17 Google 전송 전 읽기 전용 P0 메타데이터 점검 도구

- 기존 운영자 `P0_OFFLINE_VERIFY_PASS` 20개 암호문 실제 검증은 이미 확인됨. 그 암호화 사본을 수정하거나 원본 OneDrive를 다시 열 필요 없음.
- Windows 사전검사 도구 `Day12_P0_Google_Transfer_Preflight_READ_ONLY.ps1`는 `%LOCALAPPDATA%/Geumyi-P0-Encrypted-Staging`에서 가장 최근 완료 표시가 있는 암호화 폴더의 **정확한 23개 파일명·크기·파일 속성**을 관측한다. 암호문 내용과 비밀키는 읽지 않음.
- Google Drive는 `G:\` 마운트 루트 존재 정보만 확인하고 자식 폴더를 검색하지 않음. 계정 정체성, 동기화 업로드 완료, 클라우드 원격 존재와 독립 다운로드를 이 검사로 확인했다고 주장하지 않음.
- 합성 PowerShell 테스트는 파일 20개+메타데이터 3개 존재 검증, 추가 파일/누락 파일 거부, 경로 제한을 검증. [CI #38954822820](https://github.com/geumyi22/Geumyi-Minecraft-System/actions/runs/38954822820) Windows PowerShell 5.1/7 **SUCCESS**.
- 패키지 `Geumyi-Day12-P0-GOOGLE-PREFLIGHT-READ-ONLY-v1.zip` 4,492 bytes SHA-256 `c84139afd8f217971cb053cee7e4d92edd9d44115f7a307de4a23ef4a76b7397`. ZIP 내부 3개 페이로드 SHA256가 BUILD-INFO 메타데이터와 일치.
- 운영자 실제 PC 사전검사 결과는 아직 미제출. `P0_CLOUD_TRANSFER_PREFLIGHT_REVIEW_READY`이더라도 G: 실제 쓰기/암호문 업로드·독립 다운로드·실서비스 복원은 미실행이며, **업로드는 명시 동의 후 별도 검증된 절차로 진행한다**. P0/P1/Stable release gate 계속 거부.

## 2026-10-17 운영자 Google Drive 암호문 복사 승인 및 실행 경계

- 운영자가 이전 로컬 AES-GCM 독립 복호화 PASS 이후 `P0_CLOUD_TRANSFER_PREFLIGHT_STATUS=P0_CLOUD_TRANSFER_PREFLIGHT_REVIEW_READY`, `P0_ARCHIVE_SET_STATUS=LOCAL_P0_ENCRYPTED_SET_METADATA_COMPLETE`, `P0_ENCRYPTED_PARTS=20`, `P0_ARCHIVE_ENTRIES=23`, `P0_ARCHIVE_BYTES=81413`, `G_MOUNT_ROOT_PRESENT=True` 실서버 출력을 공유.
- 같은 보고서는 Google 계정 독립 식별, Google 서버 원격 사본, 업로드 및 다운로드를 모두 `false`로 기록한다. G: 마운트 성공은 실제 동기화/클라우드 업로드 보증이 아니다.
- 운영자가 **정확히 해당 23개 기존 P0 암호화 백업 구성 파일을 Google Drive의 확인된 2TB 계정으로 업로드하는 작업을 명시 승인**했다. 이 승인은 로컬 원본 파일 수정·삭제, OneDrive 원본 열람, 서버 재시작, Other Paper 기동, 외부 비밀번호 노출 또는 Stability 게이트 변경 승인이 아니다.
- 새 `Day12_P0_Google_Encrypted_Copy.ps1`는 검증된 `%LOCALAPPDATA%/Geumyi-P0-Encrypted-Staging/P0-*` 최근 완료 폴더의 23개 파일만 입력으로 사용한다. 실제 운영자 보고 크기 **81,413바이트**와 다르면 중단하며, 매 파일 SHA-256을 복사 전·후와 G: 마운트 사본에서 비교하고 정확히 23개/합계를 검증한다.
- 목적지는 사용자가 G:의 최상위 `My Drive`/`내 드라이브` 폴더를 **직접 확인해 입력**한다. 새 고유 이름의 `Geumyi-P0-Encrypted-Config-...` 하위 폴더를 **신규 생성**, 기존 파일 덮어쓰기/원본 삭제/평문 추출 없이 암호문과 검증용 메타데이터만 복사한다. 파일 복사 직전 `GOOGLE_P0_ENCRYPTED_UPLOAD_APPROVED` 추가 확인을 요구한다.
- 복사 중 실패하면 불완전 Google 폴더가 남을 수 있으며 **성공으로 보고하거나 자동 삭제하지 않는다**. Google 웹 확인·독립 재다운로드·SHA256/AES-GCM 재검증 전까지 `P0_GOOGLE_REMOTE_UPLOAD_VERIFIED=false`이고 P0/P1/Stable gate 역시 false.
- CI는 G: 운영 Google 계정이 아닌 임시 합성 경로에서 no-overwrite·정확한 23개·누락/변조 거부와 파일별 SHA 검사를 실시한다. G: 실제 동기화는 사용자 PC에서만 관찰 가능.

## 2026-10-17 Google G: 암호화 백업 신규 복사 운영 도구 검증

- [GitHub Actions #38963341571](https://github.com/geumyi22/Geumyi-Minecraft-System/actions/runs/38963341571): **Windows PowerShell 5.1과 7 synthetic 23-file copy/hash + missing/overwrite refusals PASS**, PowerShell syntax and source safe-operation checks PASS, Windows operator ZIP packaging PASS.
- `Geumyi-Day12-P0-GOOGLE-ENCRYPTED-COPY-v1.zip`: 8,990 bytes, SHA256 `b496cb18c7047c7dea9198b8969c12901ac6f849682352995fd8086bb5e28c5c`. CI artifact에서 이중 ZIP 분리 및 내장 `BUILD-INFO-P0-GOOGLE-COPY.json`에 기록된 정확한 4개 페이로드 SHA-256 대조 성공. 소스 Git HEAD `f6c632d8b9039a25c4e061411e3d9e165a24c539`. 한국어 `내 드라이브`를 Windows PowerShell 5.1에서도 파싱하도록 UTF-8 BOM 보존 확인.
- 운영자 실행: 새 ZIP을 서버 PC의 로컬 디렉터리에서 풀고 `RUN_Day12_P0_Google_Encrypted_Copy.cmd` 실행; G: 루트에서 `My Drive` 또는 `내 드라이브`가 올바른 계정임을 확인하고 **그 기존 폴더 전체 경로**를 붙여넣은 뒤 `GOOGLE_P0_ENCRYPTED_UPLOAD_APPROVED`를 입력.
- 신규 Google 하위 폴더에 `header.json`, `manifest.gcm`, `LOCAL_CAPTURE_VERIFIED.txt`, `part-000.gcm`~`part-019.gcm`만 신규 생성. 읽기는 검증된 로컬 암호문에만 한정; 파일마다 로컬 원본 복사 전/후 SHA-256 및 G: 복사본 SHA-256 대조. 기존 로컬/OneDrive 원본은 삭제하지 않음; 서버·서비스·Google 계정 동기화 설정 변경 없음.
- 현장 PC **실제 Google G: 파일 복사는 아직 실행됐다는 증거 없음**. 실행 결과 `P0_G_MOUNT_COPY_HASH_VERIFIED=23` 이후에도 Google 웹 원격 파일 존재·별도 다운로드·AES-GCM 독립 재검증까지 해야 독립 클라우드 보관 증거가 된다. G: mounted hash verification만으로 완료 선언 금지.
- 일부 복사 실패 시 해당 새 Google 폴더가 부분 상태로 남을 수 있으므로 자동 삭제하지 않고 성공 아카이브로 취급하지 않음. 오류 코드만 공유, 무분별한 재시도/중복 생성 금지. PR #53 Draft, P0/P1/Stable 전체 게이트 false.

## 2026-10-17 Google G: 전송 실행기 거짓 성공 반환 결함 — 확인 및 수정

- 운영자가 전송 ZIP 실행 출력의 CMD 헤더와 `[MOUNT COPY PASS]`만 공유. **업로드 경로 입력·수동 승인 질문·스크립트의 `P0_G_MOUNT_COPY_HASH_VERIFIED=23` 및 `P0_G_MOUNT_COPY_COMPLETE=true`가 전혀 표시되지 않음.** 이 출력만으로 로컬→G: 복사/원격 업로드 성공이라고 주장하지 않는다.
- Draft PR #53의 `Day12_P0_Google_Encrypted_Copy.ps1`에서 동일 명칭 `$FunctionsOnly`를 `Day12_P0_Google_Transfer_Preflight_READ_ONLY.ps1`의 dot-source import와 엔트리포인트에 함께 사용해, import 파라미터 바인딩이 호출자 변수에 영향을 주면 **운영 메인 로직이 스킵되고 프로세스 exit 0이 반환되는 결함**이 있었다.
- 수정: 보조 스크립트 import 전에 호출 모드 `$script:P0_Copy_EntryMode`를 별도 보존, 운영 진입 시 `P0_GOOGLE_COPY_ENTRYPOINT_STARTED` 출력. CMD 파일은 종료코드 0만으로 `[MOUNT COPY PASS]`를 표시하지 않으며 **해시 검증·복사 완료 두 P0 상태 줄**이 없으면 성공으로 처리하지 말라고 안내한다.
- Windows PowerShell 5.1/7 자동화에서 **실제 메인 엔트리포인트를 빈 `LOCALAPPDATA`로 실행해** 실패 코드·진입 메시지를 반환하고 성공을 거짓 보고하지 않는 회귀 테스트를 추가. 이 테스트는 G:와 실제 서버/OneDrive를 만지지 않는다.
- **현재 현장 G: 복사 증거 없음, Google 클라우드 원격 저장/재다운로드 미확인.** 기존 암호화 로컬 백업 20개/23개 항목·81,413바이트 및 이전 독립 AES-GCM PASS는 유효한 관측으로 유지. 이전 ZIP 재실행 금지; 수정 CI PASS·새 ZIP 검증 후에만 진행한다.

### 수정된 운영 ZIP 빌드 및 CI 증거

- **[GitHub Actions #38997640572](https://github.com/geumyi22/Geumyi-Minecraft-System/actions/runs/38997640572)**: 신규 `Regression - production entrypoint must not silently return zero` Windows 회귀 테스트 SUCCESS; `Copy simulation in Windows PowerShell 5.1 and 7` SUCCESS; `Build and verify exact operator ZIP` SUCCESS.
- 수정 운영 아티팩트: `Geumyi-Day12-P0-GOOGLE-ENCRYPTED-COPY-FIXED-v1.1.zip`, **9,224 bytes**, SHA256 `df58b97059d2633b2a56e905aaca05b0c3e1c6ebf1470bd74a8e1d6445d3b34b`. 중첩 CI 아티팩트에서 내부 ZIP 추출, 5개 엔트리 이름 및 BUILD-INFO 기록 4개 페이로드 SHA256 일치 독립 확인.
- 이전 `[MOUNT COPY PASS]`만 보였던 **결함이 있는 ZIP은 폐기/재실행 금지**. 사용자가 기존 로컬 암호화 P0 아카이브를 재생성하지 않고 새 ZIP에서 기존 23개 암호문만 G: 신규 폴더에 복사하는 단계로 재진입해야 한다.
- 수정본의 실서버 Google 복사 PASS가 아직 수신되지 않았으므로 실제 원격 업로드/재다운로드 검증은 모두 미완료. `P0_G_MOUNT_COPY_HASH_VERIFIED=23`과 `P0_G_MOUNT_COPY_COMPLETE=true` 두 출력이 없으면 PASS 아님.

## 2026-10-17 Google Drive 데스크톱 미러링 경로 확인 및 전송 방식 전환

- 운영자가 탐색기 스크린샷으로 `Google Drive (G:)` 루트의 `내 드라이브`가 **바로 가기**인 것을 보여 주었고, 이를 열었을 때 Windows 사용자 프로필의 별도 C: `내 드라이브` 폴더로 이동하는 상태를 확인했다. Google Drive for desktop 환경설정에서 **파일 미러링 선택 및 해당 C: 폴더 연결**을 운영자가 명시 확인했다.
- 기존 전송 프로그램은 G: 하위 실제 디렉터리만 허용했기 때문에 `P0_GOOGLE_COPY_GOOGLE_MYDRIVE_PATH_NOT_VERIFIED`로 **파일 복사 전에 안전 차단**되었다. 이는 업로드 성공이 아니며 이전 `P0_OFFLINE_VERIFY_PASS`와 별개다.
- 신규 미러링 전용 동작: 프로필 직속 `My Drive`/`내 드라이브` 폴더만 후보로 받고, 운영자 G: 루트의 대응 `.lnk` 바로 가기 대상 경로를 Windows Shell API로 해석하여 해당 C: 후보의 정규화 절대경로와 **실제로 일치**할 때만 신규 폴더로 23개 암호화 설정 백업 항목을 복사한다. 단순 C: 경로 문자열 확인만으로 업로드 성공을 주장하지 않는다.
- G: 원격 DriveFS와 C: 로컬 미러 폴더의 모델은 다르다. C: 미러 폴더에 있는 복사본의 SHA-256이 일치해도 **Google 원격 서버 업로드 완료·계정 독립 식별·다운로드 복구 가능성은 별도 검증**한다.
- Windows PowerShell 5.1/7 가짜 파일 및 가짜 `.lnk` 대상 동등성 테스트를 합성 CI에 추가. 실제 Google 계정/원본 서버/기존 로컬 P0 아카이브를 테스트에 사용하지 않는다. 이전 v1.1 업로드 도구는 재실행하지 않는다.

## 2026-10-17 Google Drive 미러링용 암호문 전송 도구 V2

- 사용자 실호스트에서 Google Drive for desktop의 **내 드라이브 파일 미러링**과 C: 사용자 프로필 아래 실제 미러링 폴더 일치를 재확인했다. G: 루트 항목은 파일 본체가 아니라 해당 미러 폴더로 이동하는 바로 가기.
- 수정 코드는 반드시 `P0-CheckMirrorParent(C:입력경로, USERPROFILE, G:)`를 수행한다. 대상은 사용자 프로필 직속 `내 드라이브` 또는 `My Drive`라는 이름의 *정규 디렉터리*이고, G: 루트의 동명 `.lnk` 바로 가기를 Windows Shell COM을 통해 해석한 **TargetPath가 입력 폴더와 정확히 같아야** 한다.
- 미러링 폴더가 아니거나 바로 가기 대상이 바뀌면 파일을 한 개도 쓰기 전에 `P0_GOOGLE_COPY_GOOGLE_MIRROR_SHORTCUT_TARGET_NOT_VERIFIED` 또는 `P0_GOOGLE_COPY_GOOGLE_MIRROR_SHORTCUT_CHANGED`로 중단한다.
- 복사는 확인된 C: 미러링 폴더에 새 고유 하위 디렉터리 하나를 생성하고 기존 암호화 P0 23개 파일(81,413바이트)을 SHA-256 전후 대조하여 복사한다. 로컬 P0 기존 파일은 읽기만 하고 삭제·덮어쓰기·복구 암호 노출·OneDrive 원본 접근 없음.
- 출력 `P0_GOOGLE_MIRROR_COPY_HASH_VERIFIED=23`와 `P0_GOOGLE_MIRROR_COPY_COMPLETE=true`는 **C: 미러링 로컬 복사의 완료**만 의미한다. Google 원격 업로드 성공은 비동기 별도 단계(웹 확인 + 실제 원격 사본 별도 다운로드 + 격리 AES-GCM 확인)까지 미확인으로 유지.
- 테스트에 가짜 C: 미러링 폴더와 G: 대신 쓰는 임시 폴더, 임시 `.lnk`를 생성해 PowerShell 5.1/7에서 링크 일치와 불일치 거부를 검증한다. 실제 클라우드 계정이나 서버 파일은 CI에서 읽지 않는다.
