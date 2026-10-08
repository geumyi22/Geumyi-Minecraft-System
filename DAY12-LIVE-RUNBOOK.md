# Day 12 — Live Completion Runbook

이 문서는 **지금 GitHub/CI에서 준비할 수 없는 실제 서버 PC·클라이언트 작업만** 남긴 실행 순서입니다. 현재는 실행할 필요 없습니다.

## 원칙

- 앞 단계가 FAIL/CHECK면 다음 변경 단계로 넘어가지 않습니다.
- READ-ONLY 수집은 서버를 변경하지 않습니다.
- Golden backup / managed content / known-good cache 같은 변경 단계는 명시 확인 문자열이 없으면 실행되지 않습니다.
- 실제 Java/Bedrock/GSCM 확인 없이 Day 12 COMPLETE 또는 Stable final을 선언하지 않습니다.

## 2026-10-09 실행 상태 — 중복 실행 방지

- 12.0A READY (02:45), 12.0B Golden 4/4 PASS (03:23), 12.7 cache Build PASS (03:45)는 `DAY12-REPO-PROGRESS.md`의 운영자 기록으로 확인했습니다. 이미 확보된 복구 지점을 임의로 새로 만들거나 덮어쓰지 않습니다.
- 12.10 Final Verification 실제 실행(03:47)은 **18 PASS / 0 WARN / 1 FAIL**, 실패 항목은 `backend_ports_private`입니다. 다음 우선 작업은 실서버 Windows의 **읽기 전용 TCP 바인딩 진단**(`tools\\day12\\Day12_TCP_Bind_Diagnostic_READ_ONLY.cmd`)으로 25570~25573 backend 포트가 실제로 루프백에만 바인딩되는지 확인하는 것입니다.
- 진단이 불명확하거나 외부 바인딩이 발견되면 `12.10` PASS로 처리하지 않습니다. 방화벽/서버 바인딩을 이 수집 도구가 자동으로 변경하지 않습니다.
- 아래 1~3단계는 전체 절차의 참고용이며, 이미 PASS인 지점을 **다시 실행하라는 지시가 아닙니다**. 아직 대기인 단계부터 진행합니다. 모든 `FINAL-RELEASE-GATES.json` live gate는 실제 근거 검토 후에만 닫습니다.

## 최신 READ-ONLY 일괄 수집 결과 (2026-10-09 04:23 KST)

- 전체 수집 ZIP: `Geumyi-Day12-READONLY-20261009-042239.zip` (운영자 보관, 공개 GitHub 업로드 금지). Collector 결과 `CHECK_REQUIRED`, 7단계 CAPTURED / 12.10 CHECK.
- 12.3 Live Health: **15 PASS / 0 WARN / 0 FAIL**. 12.4 Dry-run은 backup/log 정리 후보 **0건**, 따라서 현 상태에서 Lifecycle Apply를 실행할 이유가 없습니다.
- 12.2 인벤토리는 수집됐지만 GST/GDS/StatusAgent/Technology/Chemistry의 정확한 실설치 JAR fingerprint는 미확인입니다. 12.1 managed manifest에는 활성 항목이 없어 pack apply/E2E를 완료 처리할 수 없습니다.
- 12.5는 TCP listener inventory가 불명확하고 firewall Allow 규칙 범위를 충분히 확인하지 못해 보안 승인 보류입니다.
- 12.10 Final Verification은 **18 PASS / 0 WARN / 1 FAIL**, `backend_ports_private` 실패입니다. 먼저 서버의 리스너/실제 바인딩 정보를 읽기 전용으로 확인합니다. 로컬 접속 성공만으로 보안 PASS 처리하지 않습니다.
- 이미 PASS인 Golden 4개 백업과 캐시를 재생성하지 않습니다. 다른 단계가 CAPTURED라는 이유로 서버 재시작·팩 적용·Trash 이동을 진행하지 않습니다.

## 다음 증거 수집 — 12.10 TCP 바인딩 검사 (2026-10-09)

- 사용자 제출 04:22–04:23 전체 READ-ONLY ZIP 기준 12.3은 15 PASS, 12.10은 `backend_ports_private` 단독 FAIL. Golden 백업은 재실행하지 않습니다.
- 2026-10-09 05:27 수집에서는 4개 서버 모두 `server-ip=127.0.0.1` 설정을 확인했지만, TCP 제공자 3종이 2회 모두 관련 LISTENING 행을 확보하지 못했습니다. **수집 당시 GSC 서버 online 여부는 해당 보고서에 없어 확정할 수 없습니다.**
- 갱신된 도구는 GSC 서버별 online 상태를 수집 전후로 기록하고 TCP loopback 연결 결과도 같은 실행에서 확인합니다. 소켓 주소 증거가 없는 상태에서는 여전히 FAIL입니다.
- 새 `tools\\day12\\Day12_Phase10_Bind_Evidence_READ_ONLY.cmd`는 실제 서버 PC에서 4개 Paper의 `server.properties` 중 **네트워크 관련 필드만** 읽고, Windows TCP 리스너 목록을 두 번 수집합니다. 읽기 전용이며 다른 properties, 비밀번호, 전체 경로는 보고서에 넣지 않습니다.
- 결과는 `바탕화면\\Geumyi-Day12-Bind-Evidence\\Day12-Bind-Evidence-*.json`으로 저장됩니다. 보고서 `CAPTURED_REVIEW_REQUIRED`는 정상 수집 결과이지 보안 PASS가 아닙니다.
- `server-ip`가 비어 있거나 wildcard/non-loopback이라면 운영 중 직접 설정을 바꾸지 않고 **백업·서버별 점검·승인된 재시작 계획**을 세웁니다. 다른 진단 제공자가 리스너를 찾지 못하면 최종 검사기는 계속 FAIL로 둡니다.
- 실서버 바인딩 확인 전에는 `FINAL-RELEASE-GATES.json`과 Stable/Maintenance를 변경하지 않습니다.

## 05:34 데이터와 다음 단일 검사

- `Day12-Bind-Evidence-20261009-053405.json`: GSC는 Wild/Playground/Lobby ONLINE, Other OFFLINE을 수집 전후로 동일하게 보고하며, Java loopback 연결 결과도 해당 상태와 일치합니다. 4개 서버의 `server-ip=127.0.0.1` 설정은 확인됐습니다.
- 그런데 PowerShell/.NET/netstat 리스너 열거는 2회 모두 대상 0행입니다. **서버 접속 OK와 공개 포트 비노출은 별개**이므로 12.10은 FAIL을 유지합니다. RCON의 실제 LISTEN 바인딩도 별도 증거가 필요합니다.
- 최신 Operator Kit의 `Day12_Phase10_Bind_Evidence_READ_ONLY.cmd`는 이제 Windows Native `GetExtendedTcpTable`, Java 프로세스 PID, 관리자 권한 여부와 포트 프록시 *포트 번호 언급 여부만* 추가로 출력합니다. 관리자가 실행해도 운영 설정·서비스·방화벽은 변경하지 않습니다.
- 필요할 때 서버 PC에서 **마우스 우클릭 → 관리자 권한으로 실행**하여 한 번만 재수집하고 `Geumyi-Day12-Bind-Evidence\\Day12-Bind-Evidence-*.json`을 검토합니다. 전체 ZIP·백업·복구 포인트를 다시 만들 필요는 없습니다.

## 다음 테스트 — 별도 Windows PC의 LAN 접근성 (05:40 진단 이후)

- 관리자 권한 진단에서 Windows Native `GetExtendedTcpTable`은 **Playground 25571만** `127.0.0.1` 리스너로 확인했습니다. Wild와 Lobby의 25570/25573은 GSC ONLINE + 로컬 TCP 접속 성공이지만 실제 리스너 주소가 수집되지 않아 최종 보안 게이트를 여전히 통과할 수 없습니다.
- **서버 PC가 아닌 서브 Windows PC**에서 최신 Day12 Operator Kit의 `tools\\day12\\Day12_Phase10_LAN_Proof_READ_ONLY.cmd` 실행. 서버 PC의 사설 LAN IPv4를 입력합니다(127.0.0.1이나 공인 IP 금지). 해당 IP는 보고서에 저장되지 않습니다.
- 다른 PC에서 공개 입구 25565/25566/25567과 비공개 Java 25570–25573 및 RCON 25575/25576/25577/25579를 TCP 연결만으로 교차 검사합니다. 결과 `바탕화면\\Geumyi-Day12-LAN-Proof\\Day12-LAN-Proof-*.json`을 이 대화에 제출합니다. 원본을 공개 GitHub에 업로드하지 않습니다.
- **주의:** Java/RCON 비공개 포트가 원격에서 CONNECTED이면 보안 검토가 필요합니다. 모든 비공개 포트가 NO_CONNECTION이어도 방화벽 또는 네트워크 경로 영향이 있으므로 *바인딩 127.0.0.1의 증명*으로 간주하면 안 됩니다. 공개 대조 포트도 모두 NO_CONNECTION이면 LAN 테스트 자체가 미검증입니다.
- 테스트 이후에도 12.10과 Final Stable/Maintenance는 실제 증거 기준 FAIL/PENDING을 유지합니다. 서버 설정·방화벽·백업·서버 실행 상태는 변경하지 않습니다.

## 05:52 원격 LAN 검사 결과 및 중복 테스트 방지

- 실서버와 별도 서브 PC의 `Day12-LAN-Proof-20261009-055112.json`에서 공개 Java TCP **25565/25566/25567 모두 연결 성공(3/3)**, 내부 Java **25570/25571/25572/25573 모두 연결 실패(0/4)**, RCON **25575/25576/25577/25579 모두 연결 실패(0/4)**를 확인했습니다. 보고서는 읽기 전용이며 IP·토큰·비밀번호를 수출하지 않습니다.
- **LAN 접근 차단 하위 검사 PASS (테스트한 사설 LAN 경로 한정).** 방화벽과 라우팅도 접속을 막을 수 있으므로 이것만으로 실제 Java/RCON 소켓 바인딩 주소 전체가 loopback이라고 증명된 것은 아닙니다. Tailscale·인터넷 등 다른 경로도 시험하지 않았습니다.
- **12.10 최종 검증기 FAIL 유지:** Wild/Lobby 및 RCON 실제 listener bind 증거가 불충분합니다. 다시 같은 LAN 포트 테스트를 반복할 필요는 없습니다. `FINAL-RELEASE-GATES.json`은 수정하지 않습니다.
- 다음 우선순위: **12.2 미확인 자체 플러그인 JAR SHA-256 지문 대조 → 12.5 ACL/방화벽 규칙 범위 검토 → 12.10 자체 Windows 리스너 계측 보완**. 이는 모든 미완료 단계를 PASS로 변경한다는 뜻이 아닙니다.

## 다음 단일 수집 — 12.2 설치 JAR SHA-256 및 12.5 ACL/방화벽

- 서버 PC에서 최신 Operator Kit의 `tools\\day12\\Day12_Phase2_5_Integrity_Security_READ_ONLY.cmd` 파일을 **관리자 권한으로 실행**. 서버·방화벽·백업·플러그인 설치 상태는 수정하지 않습니다.
- `바탕화면\\Geumyi-Day12-Integrity-Security\\Day12-Integrity-Security-*.json` 하나만 이 대화에 제출. ZIP 전체 수집 또는 Golden 백업을 재실행할 필요는 없습니다.
- JAR SHA-256은 **현재 설치 파일 지문**이지 공식 릴리즈와 일치한다는 뜻이 아닙니다. `PENDING` / 중복 설치 / 파일명 차이는 변경 전에 검토합니다. StatusAgent는 한정된 경로 검색이므로 `NOT_FOUND_IN_LIMITED_SEARCH_SCOPE`가 나오면 설치 오류로 단정하지 않습니다.
- 방화벽 결과는 필터별 허용 범위 *검토 자료*입니다. 특정 허용 규칙이 있다고 실제 노출을 단정하거나 LAN 미연결만으로 모든 인터페이스의 바인딩 보안을 입증하지 않습니다.
- Day 12.10 `backend_ports_private`와 최종 Stable 게이트는 그대로 **FAIL/PENDING**입니다.

## 06:02 검토: 12.2·12.5 검사 도구 수정 및 한 번만 재수집

- 로비의 GST/GDS 짧은 이름은 `tools/day10/finish_day10.ps1`에서 의도한 배포 이름으로 확인됐습니다. 현재 JAR 해시가 다른 서버와 달라 **바이너리 동일성은 미검증**이지만, 이름만으로 대체·삭제하지 않습니다.
- 최초 Agent 검사에서 0.4.5가 발견됐으나, 실제 GSC 서버 역할 Agent 경로인 `ProgramData/GeumyiServerCenter/Runtime/Agent`는 검색하지 않았습니다. **기존 버전을 실행 중이라고 단정하지 않습니다.** 도구를 수정해 0.5.4 실설치 후보와 설정된 `agent.jar_name`을 읽기 전용으로 확인하도록 했습니다.
- GSC 데이터 폴더 ACL에 BUILTIN_USERS inherited write/modify Allow 1건이 표시됐습니다. 악용 가능성이나 유효 권한은 추가 검증 전까지 확정하지 않으며, **ACL 상속/소유권/보호 복구 경로를 임의로 변경하지 않습니다**.
- 이전 방화벽 149 matching rows는 142건이 `LocalPort=Any`여서 어떤 대상 포트를 명시적으로 연 것은 아닙니다. 새 도구에서는 `Any` 포트를 특정 포트 OPEN으로 세지 않고, 서비스·프로그램·프로필 범위를 추가 기록합니다. 적용 중인 효과를 완전히 확정하는 보고서는 아닙니다.
- 다음 한 번만: 최신 Operator Kit → 서버 PC 관리자 권한으로 `tools\\day12\\Day12_Phase2_5_Integrity_Security_READ_ONLY.cmd` 실행 → 새 `Day12-Integrity-Security-*.json` 한 개 제출. 이전 LAN/Golden 백업/전체 진단은 반복하지 않습니다.
- 이 결과를 검토하기 전까지 플러그인 재배포, StatusAgent 제거, 방화벽과 폴더 ACL 변경, 12.10 PASS 및 Stable 전환은 보류합니다.

## 06:07 후속 결과 — Agent 경로 확인 / 방화벽 수집 오류

- `Day12-Integrity-Security-20261009-060757.json`: `Runtime/Agent/GeumyiStatusAgent-0.5.4.jar` 파일과 GSC 설정값이 일치함을 확인했습니다. 같은 실제 런타임 디렉터리의 0.5.3 파일과 레거시 위치 0.4.5 파일은 **자동 삭제 금지**입니다. 파일 존재로 현재 실행 중인 Agent 버전을 증명할 수는 없습니다.
- 방화벽은 268개 활성 인바운드 규칙을 열거했지만 `ERROR_OR_UNAVAILABLE`이며 실제 조건별 필터 목록이 비어 있습니다. **이 결과로 보안 PASS 또는 방화벽 문제 없음 판정 금지.** 먼저 진단기가 여러 규칙을 처리하도록 수정했습니다.
- 수정된 도구는 wildcard 포트 처리 시 PowerShell StrictMode에서 null이 될 수 있는 배열을 직접 초기화하고, 필터/규칙별 예외를 신상정보 없이 단계·예외 종류만 기록합니다. 방화벽 검사 부분이 실패하면 전체 결과는 `CHECK_REQUIRED`로 반환하게 했습니다.
- 최신 Operator Kit Safety CI를 확인한 후 **서버 PC에서만** `tools\\day12\\Day12_Phase2_5_Integrity_Security_READ_ONLY.cmd` 관리자 권한 실행 → 새 JSON **하나** 제출. 이전 LAN 검사/Golden 백업/기존 보고서를 재실행하지 않습니다.
- 진행 중인 서버나 Windows 방화벽/폴더 ACL/플러그인/Agent 프로세스를 진단을 위해 변경하지 않습니다. 12.10 최종 보안 검증 및 Stable 게이트는 계속 미통과입니다.

## 06:13 후속 — 방화벽 수집 성공, 이제 범위 위험성 검토

- `Day12-Integrity-Security-20261009-061224.json` 확인: `firewall.status=CAPTURED`, 268/268 인바운드 활성 규칙 처리 완료, 규칙/필터 오류 모두 0. 따라서 **같은 12.2+12.5 전체 수집을 반복할 필요 없습니다**.
- 대상 47개 허용 규칙 중 38개는 `Any` 포트/프로그램/서비스와 원격주소 `Any`로 분류된 **광범위 규칙 후보**입니다. 이 규칙들이 해당 PC에서 실제로 적용되는지는 활성 방화벽 프로필, 규칙 출처, 인터페이스/패키지·기타 보안 조건까지 검토해야 합니다. 현 시점에 즉시 규칙을 일괄 비활성화하거나 삭제하면 기존 마인크래프트·Tailscale·원격 관리 연결에 영향을 줄 수 있으므로 **변경 금지**.
- 명시적 대상 허용: `TCP 25565,25566` 원격 Any, `UDP 19132,19133` 원격 Any, `TCP 8787` 원격 LocalSubnet. 특히 관리 API 8787은 **실제 바인딩 주소/인증/방화벽 효과**를 별도로 확인해야 합니다. 이전 Native 8790 loopback 증거는 8787 바인딩 증거를 대신하지 않습니다.
- GSC ProgramData의 상속된 BUILTIN_USERS 쓰기 Allow 1건은 수정하지 말고, 장기적으로 서비스/백업 권한을 포함한 유효 권한 확인 후 계획적으로 최소 권한화합니다.
- StatusAgent 0.5.4 JAR과 설정 일치, 구버전 파일 공존 확인. 현재 **실행 파일 버전**과 GitHub 공식 SHA-256 신뢰성은 별도 판정. 서브 PC LAN 접근 차단은 기존 증거 유효.
- 남은 것: 12.5 실제 정책/ACL 확인, 12.10 백엔드 Java/RCON 소켓 바인딩, 12.11 Java+Bedrock+GSCM 실기기 E2E 등. `FINAL-RELEASE-GATES.json` 및 Stable 전환 보류. 새로운 변경/증거가 생기지 않는 한 기존 전체 보고서/Golden/LAN 테스트 재실행하지 않습니다.

## 06:13 다음 단일 검사 — 광범위 방화벽 정책 ActiveStore 확인

- 기존 12.5 전체 검사는 `CAPTURED`로 성공했으며 **같은 전체 진단을 다시 실행하지 않습니다**. 38개 광범위 Allow 후보의 실제 적용 범위(ActiveStore·네트워크 프로필·인터페이스 종류·IPsec 조건 등)만 확인합니다.
- 서버 PC에서 최신 Operator Kit의 `tools\\day12\\Day12_Phase5_Firewall_Scope_READ_ONLY.cmd`를 관리자 권한으로 **읽기 전용 실행**. 출력: 바탕화면 `Geumyi-Day12-Firewall-Scope\\Day12-Firewall-Scope-*.json`. **새 JSON 하나**를 대화에 제출하고, 원본은 공개 GitHub에 올리지 않습니다.
- 해당 결과는 **실제 Windows Filtering Platform 패킷 접근의 최종 증명은 아닙니다**. 과도한 광범위 규칙이 밝혀져도 현재 서버 운영에 영향을 줄 수 있으므로, 어떤 규칙도 임의로 삭제/수정하지 않고 근거를 먼저 검토합니다. 필요할 경우 추후 별도 승인과 롤백 계획을 세웁니다.
- 12.10/12.13 릴리즈 게이트 유지. Golden/캐시/이전 LAN 재검사 불필요.

## 06:21 후속 — ActiveStore 수집 완료, 12.5 보안 승인 보류

- `Day12-Firewall-Scope-20261009-062054.json`으로 활성 Private/Public 프로필, 프로필별 기본 인바운드 Block, 활성 Allow 266건 및 광범위 Any/Any 후보 38건을 확인했습니다. 모두 활성 네트워크 프로필과 겹치며 로컬 원본 규칙입니다. 이들 모두 원격 IP 조건은 Any이고 36개는 로컬 IP도 Any, 2개는 로컬 주소 제한이 있습니다. **도구는 정상 동작했고 같은 ActiveStore 전체 수집을 반복할 필요 없습니다.**
- 이 정보는 규칙의 **실제 효과/원인**을 검증한 자료는 아닙니다. 규칙 이름/원본 앱이 수집되지 않아 불필요한 허용 규칙인지 판단할 수 없습니다. 특히 GSC 관리자 포트 **8787/TCP**에 대한 LocalSubnet Allow 설정은 알려져 있으나 실제 8787 접근·바인딩 상태를 아직 확인하지 않았습니다.
- 다음은 검토용으로 38개 규칙의 근거(Windows 구성요소·개발 도구·Tailscale·기타 프로그램 등)를 **기록만** 하거나 별도 PC에서 8787 접근을 **TCP connect only**로 테스트하는 것이 유의미합니다. 테스트와 설정 변경을 혼동하지 않도록 주의하며, 서비스·방화벽·ACL·백업은 바꾸지 않습니다.
- 12.5 보안 승인 보류 / 12.10 backend bind FAIL / 12.11 E2E와 12.12 soak 미실시 / 12.13 Stable 릴리즈 BLOCKED.

## 06:24 확인 — 원격 GSC 관리 포트 8787 응답과 접근통제 분리 검증

- 사용자가 서버 PC의 LAN IP를 향한 **서브 PC 8787/TCP 검사에서 `TcpTestSucceeded=True`**라고 보고했습니다. 직전 자기 자신 검사(`SourceAddress=RemoteAddress`)와 혼동하지 않으며 이번에는 SourceAddress 전체 결과가 제출되지 않아 원격 접속 여부는 사용자 실행 위치 진술 기준입니다.
- 현재 GSC Host **소스**는 실제 listener를 `0.0.0.0:8787`에 열고, 비루프백 LAN/Tailscale 접근에 대해 mobileNetworkGuard 및 protected routes token/device 인증을 적용합니다. 이는 GSCM 원격 관리 설계이므로 **8787 LAN TCP 성공을 곧바로 취약점이라고 판정하지 않습니다**. 반면 원래 숨겨야 하는 backend Java/RCON 포트의 외부 접속이 허용되는 것은 별개입니다.
- 다음 *단일* 단계는 서브 PC에서 **토큰 없이 읽기 전용** `GET /api/v1/info` HTTP 상태 코드만 확인: 정상적으로 401 (또는 네트워크 가드가 차단하는 조건이면 403). 200이면 설정/프록시/인증 경로를 조사하고 그 전에는 변경하지 않습니다. 비밀번호·Bearer 토큰·HTTP 응답 내용은 공개 채팅이나 GitHub에 올리지 않습니다.
- 이 확인이 완료돼도 12.5 ACL/WFP 실효성 및 12.10 backend socket bind gate가 자동 PASS되는 것은 아니며 Stable 릴리즈는 차단 유지. 방화벽·서비스 설정 변경/재시작 불필요.

## 06:25 원격 API 인증 후속 확인 (HTTP 401)

- 서브 PC에서 서버 PC LAN IP의 8787/TCP 연결이 가능하다고 사용자가 보고했습니다. 또한 인증 토큰 없이 `GET /api/v1/info` 실행한 결과 **HTTP 401**이 반환됐습니다. 해당 원격 경로에서는 인증 누락 요청이 거절되는 것을 확인했습니다.
- **이 하위 검사만 PASS**입니다. GSCM 원격 관리를 위해 GSC Host가 0.0.0.0에 리슨하면서 사설 LAN/Tailscale 네트워크 제한 및 토큰/등록기기 인증을 거치는 현재 소스 설계와 일치합니다. 이 결과만으로 전체 API 보호, 공인 인터넷 노출 여부, 38개 광범위 허용 방화벽 규칙의 용도/실효성, GSC 데이터 폴더 ACL을 검증했다고 처리하지 않습니다.
- 불필요한 8787 재검사는 중단하고, 다음 우선순위는 **12.5 광범위 방화벽 규칙의 식별·필요성 및 ACL 유효 권한 검토**와 **12.10 backend Java/RCON 실리스너 바인딩 증명**입니다. 모든 변경은 명시적 승인·롤백 계획 전까지 하지 않습니다. `FINAL-RELEASE-GATES.json` 및 Stable 차단은 유지합니다.

## 다음 단일 검사 — 12.5 방화벽 규칙 용도 힌트와 GSC 파일 ACL

- 지금까지 12.2 플러그인 SHA-256, 12.5 방화벽 정책 수집, 8787 인증 `HTTP 401`, 서브 PC LAN 검사 및 Golden 백업은 **중복 실행하지 않습니다**.
- 최신 Day 12 Operator Kit에서 **서버 PC**의 `tools\\day12\\Day12_Phase5_Rule_ACL_Review_READ_ONLY.cmd`를 관리자 권한으로 실행합니다. 바탕화면 `Geumyi-Day12-Rule-ACL-Review\\Day12-Rule-ACL-Review-*.json` **최신 파일 하나**만 대화에 제출합니다.
- JSON에는 Windows 방화벽 규칙 *원문 이름이 아닌 추정 범주*와 ACL 권한 비트·상속 정보만 들어갑니다. 이름 분류가 `UNCLASSIFIED`여도 안전/악성이라고 단정하지 않습니다. 실제 유효 NTFS 권한 또는 WFP 패킷 결정까지 계산하지 않으며 `CAPTURED_FOR_REVIEW`는 최종 보안 통과가 아닙니다.
- 검사 결과에 문제가 있어도 **방화벽 끄기, ACL 수정, Agent 파일 삭제, GSC 재설치/재시작, 백업 이동, Stable 릴리즈는 실행하지 않습니다.** 필요하면 원인과 롤백 방안을 검토한 뒤 별도 단계로 결정합니다.

## 06:35 결과 — 방화벽 38개 분류와 ACL 대상 이름 출력 오류

- `Day12-Rule-ACL-Review-20261009-063544.json`: **정상 수집**. 활성 허용 규칙 266건 중 넓은 범위 후보 38건: 미분류 33, 게임 이름 힌트 3, VPN/오버레이 힌트 2. 활성 프로필 Any/Public를 포함하여 우선 검토로 분류된 항목은 15건입니다. 미분류는 **악성 판단이 아닌 이름 패턴 판별 불가**를 뜻합니다. 어떤 규칙도 이 정보만으로 중지/삭제 금지.
- ACL 결과의 `target_role` 필드가 다섯 항목 모두 `BUILTIN_USERS`로 출력된 것은 **검사 스크립트의 버그**입니다. 원본 수집 순서에 따라 [GSC ProgramData 폴더, server.json 파일, Runtime 폴더, Runtime/Agent 폴더, 0.5.4 Agent JAR]로 각각 대응합니다. ACL 권한 비트 자체가 모두 같은 값이라는 뜻이 아닙니다. GitHub에서 `$role`과 `$Role` 충돌을 수정했고 synthetic 검사를 추가했습니다.
- `server.json`과 Agent JAR 파일 직접 ACL은 BUILTIN_USERS의 데이터 쓰기/삭제를 허용하지 않는 것으로 관찰됐습니다. 그러나 [GSC ProgramData, Runtime, Runtime/Agent] 디렉터리는 BUILTIN_USERS에 **ContainerInherit** 파일·하위 폴더 생성 권한이 상속돼 있습니다. 이 ACE만으로 기존 파일을 바꿀 권한이 보장되는 것은 아니지만, 안전하다고 확정할 수 없습니다. 원 검사기는 디렉터리 `DeleteChild` 비트를 누락했으므로 수정 버전에서 기록합니다.
- **실제 권한 변경은 수행하지 않습니다.** 디렉터리 ACL 상속 해제나 광범위 방화벽 규칙 비활성화는 GSC 시작/업데이트/백업에 영향을 줄 수 있습니다. 새 도구를 실행한다면 수정 버전에서 **ACL 대상명과 `delete_children`만 추가로 확인**하면 됩니다. 앞서 통과한 방화벽/Agent SHA/LAN/골든 검사 전부 재실행 금지.
- 12.5 최종 검증 보류, 12.10 FAIL, Stable 차단 유지.

## 다음 한 번만 — 12.5 ACL 라벨·하위 파일 삭제권 보정 수집

- **서버 PC** 최신 Operator Kit에서 `tools\\day12\\Day12_Phase5_ACL_Only_READ_ONLY.cmd`를 **관리자 권한으로 실행**. 바탕화면 `Geumyi-Day12-Rule-ACL-Review\\Day12-Rule-ACL-Review-*.json` 중 새 파일 하나만 제출하세요.
- 이 명령은 `-AclOnly`를 사용하므로 기존 **방화벽 266개 규칙 재검사, GSC API 호출, Java/Bedrock 서버 설정 검사, 백업 검사 전부 건너뜁니다**. 파일 ACL 메타데이터 5건만 읽고 정확한 대상 라벨과 부모 `delete_children`을 기록합니다. `server.json` 내용과 계정/비밀정보는 파일로 내보내지 않습니다.
- 새 ACL 결과가 깨끗하더라도 12.5 전체 보안 검증 PASS/12.10 PASS/Stable 자동 승격은 금지. 사용자별 effective access, 방화벽 미분류 33개 정당성, 실제 backend listener 주소는 별도 확인 사항입니다. 이미 성공한 전체 검사·LAN 검사·골든 백업은 반복 금지.

## 1. 한 번에 READ-ONLY 수집

서버 PC에서 tools\day12\Day12_Collect_All_READ_ONLY.cmd 실행.

필수 확인:
- 12.0A unresolved mandatory CHECK 없음
- GSC 4.3.8
- 4개 backend/profile
- public Java/Bedrock entry 3개
- unsafe transaction 없음
- 디스크 여유 확인

## 2. 12.0B Golden Recovery Checkpoint

Wild / Playground / Other / Lobby가 모두 이미 OFFLINE인 유지보수 창에서 tools\day12\Day12_Phase0B_Golden_Checkpoint.cmd 실행.
이 도구는 서버를 자동으로 끄지 않습니다.

PASS 기준:
- 서버별 FULL backup 생성
- ZIP/SHA 검증
- protect=true
- retention candidate에서 제외

## 3. Known-Good Cache

12.0B PASS JSON을 지정해 Day12_Phase7_KnownGood_Cache.ps1 -Mode Build -Phase0BReport <12.0B JSON> -Confirm BUILD_DAY12_KNOWN_GOOD_CACHE 실행.

## 4. ResourcePack/DataPack

먼저 Day12_Phase1_Content_Preflight_READ_ONLY.cmd 실행.
deploy/day12-managed-content.json은 기본적으로 모두 disabled입니다. 실제 검증된 ZIP/HTTPS URL/hash를 채운 항목만 활성화합니다.
Java apply는 transaction journal + 자동 rollback이 있고, 필요 시 Day12_Phase1_Managed_Content_Rollback.ps1로 명시적 수동 rollback도 가능합니다.
Bedrock/Geyser pack 위치는 실제 환경에서 확인되기 전까지 자동 apply하지 않습니다.

## 5. Runtime health/security/lifecycle

- 12.2 Component Inventory
- 12.3 Whole-System Health
- 12.4 Storage/Log DRY-RUN
- 12.5 Security Audit

보존 정책은 dry-run 결과를 검토하기 전 적용하지 않습니다. 적용 시에도 Day12_Phase4_Lifecycle_Apply.cmd는 영구삭제가 아니라 GSC Trash/LogTrash로 이동하고 로그 ZIP archive를 먼저 만듭니다. LogTrash 복구 전에는 Day12_Phase4_LogTrash_Recovery_Preflight.ps1로 archive/Trash 가용성을 확인합니다.

## 6. Offline known-good gate

업데이트 조회/외부 네트워크가 실패하는 상황에서도 GSC, Velocity, 필요한 backend가 로컬 verified artifact로 정상 시작 가능한지 확인합니다.
네트워크 차단 자체는 자동화하지 않습니다. 운영 네트워크/방화벽을 스크립트가 임의 변경하지 않도록 한 안전 결정입니다.

## 7. Canonical Final Verification

tools\day12\Geumyi_Final_Verification.cmd 실행. mandatory FAIL=0 필요.
이 검사는 실제 플레이어 로그인 검사가 아닙니다.

## 8. 12.11 Final live E2E

FINAL-E2E-REPORT.md 순서대로 Windows reboot, Host/Velocity/backend, Java, Bedrock, 운영 명령/상태 전이, backup/restore/update safety, GSCM을 확인합니다.

## 9. 12.12 Soak

Day12_Phase12_Soak_READ_ONLY.cmd에서 Start → 실제 사용/idle → End. 가능하면 8–12시간을 목표로 합니다.

## 10. Final Stable / Maintenance Mode

모든 근거가 PASS일 때만:
- FINAL 문서/JSON을 실제 근거로 갱신
- FINAL-RELEASE-GATES.json의 모든 repository/live gate를 PASS로 변경
- stable/maintenance booleans를 true로 변경
- Day 12 Final Closure Gate workflow PASS
- fail-closed `.github/workflows/day12-final-release.yml`을 통해 기존 signed Secure Release chain으로 최종 Stable 배포
- Day 12 COMPLETE
- Maintenance Mode 전환

그 전에는 Final Stable과 Maintenance Mode를 열지 않습니다.
