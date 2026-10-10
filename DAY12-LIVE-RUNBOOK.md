# Day 12 — Live Completion Runbook

이 문서는 **지금 GitHub/CI에서 준비할 수 없는 실제 서버 PC·클라이언트 작업만** 남긴 실행 순서입니다. 현재는 실행할 필요 없습니다.

## 협업 실행 기준 — 안전한 GitHub 작업은 자동 진행 (2026-10-10)

- 사용자 방침: 어시스턴트가 직접 수행 가능한 **읽기 전용 코드 검토, 안전한 소스 수정, GitHub 문서 업데이트, CI/합성 테스트, 배포 전 준비 작업은 매번 승인 질문 없이 연속 진행**. 중요한 발견은 중간 보고합니다.
- 사용자 개입은 **실제 서버 PC에서 CMD/EXE 실행이나 E2E 기기 테스트가 필요할 때**, 또는 운영 환경에 영향이 발생하는 **재시작·서비스 중단·방화벽·ACL·RCON/서버 설정 변경·백업/삭제·데이터 복구·릴리즈 승격**에만 구체적인 실행 단계/영향/안전·복구 계획을 명시하고 요청합니다. 이 일반 위임이 운영환경을 마음대로 바꿀 권한은 아닙니다.
- 테스트 미수행 상태는 실행 완료로 표시하지 않으며, 기존 **12.0 Golden 4/4, 현장 12.10 증거**와 Day1~12 임시파일 정리 지연 원칙을 유지합니다. 동일 검사를 불필요하게 반복하거나 사용자에게 이미 답한 내용을 다시 묻지 않습니다.

## 2026-10-10 운영 권한 갱신 — 일상적 서버 재시작 사전 재승인 불필요

- 사용자 답변 **"상관없음 그런건 앞으로도"**: 플레이어/백업/작업 충돌을 사전 점검한 **통상적인 개별 마인크래프트 서버 재시작·안전 점검은 매번 허락을 다시 묻지 않고** 실행 계획에 포함할 수 있습니다. 단, 어시스턴트는 서버 PC에 직접 접근할 수 없으므로 실제 PC 실행 파일은 사용자가 실행해야 합니다.
- 월드 복구/복원, 영구 삭제, Windows 전체 재부팅, 다중 서버 강제 종료, 방화벽/ACL/네트워크 보안 정책 변경, 비밀번호 변경, 롤백이 어려운 업데이트 등은 **이 포괄적 허락에 포함되지 않습니다**. 손실·중단이 큰 경우 별도 범위와 복구 절차를 확인합니다.
- 새로운 일회성 유지보수 스크립트 `tools\\day12\\Day12_Phase10_Scoped_Graceful_Restart.cmd`: 놀이터 Java 25571 / RCON 25576 한 서버만 대상으로 GSC 정식 graceful restart(15초 countdown) 실행. **GSC v4.3.8, 온라인, 플레이어 0명 확증, 동시 작업 없음, 보호+검증된 전체 Golden 백업, 안전 업데이트 상태**를 모두 만족해야 실행합니다. 재시작·증거 수집은 단 한 번, 미확인 시 차단, 강제 종료·백업 복원·설정 변경 없음. 게임 호스트에 사용자가 실행해야 하는 것은 이 CMD 한 개입니다.
- 안전 합성 CI PASS는 실서버 성공과 다릅니다. 한 번의 재시작 후에도 바인딩 주소가 확인되지 않으면 12.10 `backend_ports_private` FAIL 유지; 검증기 조건을 임의 완화하지 않습니다. 기존 자동 업데이트 정책은 서버 정상 시작 과정에서 작동할 수 있습니다. 자세한 절차: `DAY12-PHASE10-APPROVED-SCOPED-RESTART.md`.

## 2026-10-10 02:41 — Playground restart preflight false block corrected

- Operator's real Day12-Scoped-Restart-20261010-024155.json: Playground ONLINE, zero players, protected verified FULL backup present, no active jobs; result BLOCKED_UPDATE_BLOCK_START, mutation=false, restart_accepted=false. **No server restart occurred.**
- GSC defines block_start as Go bool omitempty: a missing property means false. The first script incorrectly defaulted a missing property to true. Fixed only this default; explicit true, missing update status, unsafe/unknown update phases, players, jobs and missing verified backup still block.
- After the revised Windows synthetic CI and Operator Kit are successful, operator runs the **new** tools/day12/Day12_Phase10_Scoped_Graceful_Restart.cmd once on SERVER PC, not the old blocked version, then provides only the fresh Desktop/Geumyi-Day12-Scoped-Restart JSON. No unbounded reruns.
- App startup Java/RCON loopback 8/8 remains historical evidence; live OS exclusive bind and Day12.10 canonical verification are not yet satisfied. Stable remains BLOCKED.

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

## 06:43 ACL 전용 검사 접수 — 재검사 중단 / 12.5 잔여 검토

- `Day12-Rule-ACL-Review-20261009-064327.json` 확인: 5개 ACL 대상 **전부 올바른 라벨**, `CAPTURED_FOR_REVIEW`, 오류 0건, 새 `delete_children` 비트 정상 출력, 방화벽 규칙 재검사 없음. **12.5 ACL 재수집을 반복하지 않습니다**.
- 일반 사용자 그룹 `BUILTIN_USERS`의 기존 GSC `server.json` 파일/0.5.4 Agent JAR에 직접 쓰기/삭제 허용이 없습니다. GSC ProgramData, Runtime, Runtime/Agent **디렉터리**에서는 파일/폴더 생성 허용이 관찰되지만 `Delete`, `DeleteChild`, `ChangePermissions`, `TakeOwnership`은 거짓입니다. 다섯 대상 모두 상속을 사용합니다.
- 38개 광범위 방화벽 Allow 규칙(용도 미분류 33개), 실제 NTFS 유효 권한 및 GSC Host/Updater 실행 계정은 **미검증**입니다. 해당 ACL과 규칙은 즉시 삭제·상속 해제하면 오히려 시스템이 손상될 수 있으므로 현재 **어떤 설정도 변경하지 않습니다**.
- 전체 근거·문제 범위·변경 승인 전 체크리스트: `DAY12-PHASE5-SECURITY-REVIEW.md`. `12.5` 자료 수집은 완료, 보안 게이트는 **OPEN**. 이후 중요한 차단 항목은 `12.10` Java backend/RCON 실리스너 바인딩, `12.11` E2E, `12.12` soak입니다. Golden/기존 네트워크 검사/기존 ACL 전부 재검사 금지. `12.13` Stable 계속 차단.

## 다음 단일 작업 — 12.10 새 Native TCP 테이블 종류 교차검증

- GitHub의 최종 12.10 검증기에 Windows Native `GetExtendedTcpTable` 지원을 추가했습니다. 기존 05:40 증거는 **Playground 25571 loopback만** 확인했고 Wild/Lobby/RCON의 실제 바인딩은 여전히 누락돼 있습니다. 이 패치는 PASS 판정을 느슨하게 만들지 않습니다. 오히려 GSC 온라인 Java와 RCON의 listener를 각각 확인하고, 증거 없으면 FAIL 유지합니다.
- **서버 PC 관리자 권한**으로 최신 Day 12 Operator Kit의 `tools\\day12\\Day12_Phase10_Native_Listener_Crosscheck_READ_ONLY.cmd` **단일 실행** → 바탕화면 `Geumyi-Day12-Native-TCP\\Day12-Native-TCP-*.json` 최신 하나를 대화에 제출하세요. 두 Windows Native TCP 테이블 클래스의 리스너 범위를 비교하는 새로운 정보입니다. 기존 PowerShell/netstat 검사나 독립 LAN 3/3·0/8 포트 검사를 반복하지 않습니다.
- 검사기 파일 내용과 서버 프로세스, GSC 네트워크 정책, 서버 월드, 백업, 방화벽, ACL은 변경하지 않습니다. 도구 결과 `CAPTURED_REVIEW_REQUIRED`는 자료 수집 성공이지 실제 보안 완료 판정이 아닙니다. Native에서 실서버 리스너를 여전히 찾지 못하면 **12.10 FAIL 유지**; 추후 별도 방식의 포트/프로세스 관계를 조사합니다.
- 새 보고서 검토 후 **필요할 때만** 정식 `tools\\day12\\Geumyi_Final_Verification.cmd`를 단 한 번 재실행합니다. 성공한 Golden/12.5/캐시를 재수집하거나, 12.11 E2E·12.12 soak·Stable 릴리즈를 앞당기지 않습니다.

## Day 1~12 PC 임시파일 정리 도구 — 별도 준비, Day12 종료와 구분

- 이번 정리 프로그램은 **Day12만이 아니라 Day1~Day12 전체**를 대상으로 설계했습니다. 실행 파일 `tools\\day12\\Geumyi_Day1To12_PC_Temp_Cleanup.cmd`; 설명 `DAY1-12-PC-CLEANUP-GUIDE.md`.
- 지금 가능한 첫 단계는 메뉴 **1번 Preview**뿐입니다. 서버 PC든 관리/서브 PC든 각 컴퓨터에서 개별 실행해야 하며, Windows 사용자 TEMP 폴더의 과거 임시 작업물만 좁게 탐색합니다. Desktop/Downloads는 발견 목록만 만들고 이동하지 않습니다.
- 아직 12.10 FAIL, 12.11/12.12 대기, 최종 Stable 차단이므로 **Day12 자료는 도구 자체에서 격리 불가**입니다. 이전 Day1~11 파일도 보존 검증·나이 조건(기본 7일)·리뷰된 계획과 승인 문구를 통과한 경우에만 복원 가능한 임시 격리로 이동할 수 있습니다. 영구 삭제는 14일 격리 후 별도 확인 시에만 가능합니다.
- `%ProgramData%\\GeumyiServerCenter`, 실제 서버 월드·플러그인·Golden 백업·캐시·복구·로그·설정은 제외됩니다. `plan-*.json` 및 `manifest.json`은 절대 공개 저장소에 올리지 않습니다. 정리 성공을 Day12 완료 또는 release gate PASS와 혼동하지 않습니다.

## 2026-10-10 01:12 실서버 Native TCP 결과 — 다음은 로컬 연결성 1회만

- 새 `Day12-Native-TCP-20261010-011258.json`: Native Owner PID IPv4/IPv6 및 Basic IPv4 **모두 CAPTURED**, 2회 동일, `25570` Wild Java와 `25579` Lobby RCON 실제 `127.0.0.1` LISTEN 확인. 관리 API `8787`은 `0.0.0.0`·`::` LISTEN으로 확인(이전 LAN 인증 없는 `GET /api/v1/info` HTTP 401은 별도 부분 검사).
- GSC가 ONLINE이라고 보고한 **Playground Java 25571, Lobby Java 25573, Wild RCON 25575, Playground RCON 25576**에 리스너 행이 없습니다. 기타 서버 OFFLINE에 해당하는 `25572`, `25577`은 온라인 검증의 필수 대상에서 제외합니다. 이전 05:40 25571 관측과 결과가 달라 시점별 상태나 계측 차이를 확인해야 합니다.
- **12.10 최종 PASS 금지.** 기존 05:52 서브 PC LAN 0/8 실패와 포트 설정값 `127.0.0.1`은 유용하지만 실서버 리스너 바인딩을 대신 증명하지 않습니다. 앞선 진단 도구/방화벽 전체 검사/12.5 ACL/Golden 백업을 반복하지 않습니다.
- 다음에는 새 좁은 로컬 TCP 접속 테스트로, **네이티브 테이블에서 미검출이었던 서비스가 실제 127.0.0.1로 TCP 연결되는지만** 확인합니다. 연결이 가능하면 리스너 계측 차이, 불가능하면 기동·RCON 상태부터 조사합니다. TCP 연결 자체는 소켓 주소 증명이나 실제 인증·게임 플레이 E2E가 아닙니다. 변경 전에 증거만 수집합니다.

## 다음 작업 (2026-10-10) — 오직 12.10 로컬 TCP 비교 1회

- 직전 실서버 파일 `Day12-Native-TCP-20261010-011258.json`에서 Native Owner/Basic 3방식, 2회 모두 정상 수집했으나 온라인 4개 필수 포트(`25571`,`25573`,`25575`,`25576`)가 실제 LISTEN으로 검출되지 않았습니다. `25570`과 `25579`는 `127.0.0.1` 검출. GSC API 8787은 wildcard 리슨(기존 인증 없는 API 요청 401은 별도 부분 검사).
- **서버 PC** 최신 Operator Kit의 `tools\\day12\\Day12_Phase10_Loopback_Compare_READ_ONLY.cmd`를 일반 권한으로 실행 → 바탕화면 `Geumyi-Day12-Loopback\\Day12-Loopback-Compare-*.json` 최신 파일 하나만 제출하세요. 파일 내용은 서비스별 포트 및 연결 성공 여부만 기록; 전체 Windows 재스캔·기존 LAN 진단·Golden·12.5 검사는 중복 실행하지 않습니다.
- 로컬 연결 성공은 **바인딩이 loopback 전용임을 입증하지 않습니다**. 실패는 서비스 오프라인/일시 장애/필터링 등 구분이 필요합니다. 12.10 최종 PASS 불가, 12.11/12.12/12.13 대기 유지. Windows 설정·서버 실행 상태는 변경하지 않습니다.

## 2026-10-10 01:19:56 — 12.10 로컬 TCP 검사 6/6 성공, 바인딩 증거 추가 조사

- `Day12-Loopback-Compare-20261010-011956.json`: 실서버 읽기전용 검사 **CAPTURED**. Wild Java/RCON 25570/25575, Playground 25571/25576, Lobby 25573/25579 전부 **127.0.0.1 TCP 연결 성공**; Other는 OFFLINE이라 제외. 전후 GSC fleet 그대로, 실패 0. 이 결과로 Java/RCON 소켓 로컬 연결 검사는 통과한 것으로 분리 기록합니다.
- 그러나 `01:12` Native LISTEN 캡처에서는 25570/25579만 루프백으로 관찰되고 온라인 25571/25573/25575/25576 LISTEN 행이 보이지 않았습니다. **리스너 목록 누락·프로세스 소켓 경로를 구분하기 전 12.10 정식 PASS 금지**.
- 다음 한 번만 최신 Operator Kit의 **서버 PC** `tools\\day12\\Day12_Phase10_Active_Connection_Trace_READ_ONLY.cmd` 실행. TCP 연결이 짧게 유지되는 동안 **미검출 포트 네 개**의 서버 측 `ESTABLISHED` endpoint를 관찰해 JSON에 기록합니다. 바탕화면 `Geumyi-Day12-Active-Connections\\Day12-Active-Connections-*.json` 최신 하나만 제출합니다. 관리자 권한 불필요, 명령·인증정보 없음, 소켓 handshake가 로그에 남을 수 있음. 먼저 CI 합성 시험 성공을 확인합니다.
- 유효 권한·방화벽/ACL 변경, TCP listener 보안 완전 인증, Java/Bedrock 실사용 E2E는 아직 아님. 기존 12.5/Golden/LAN/Native/Loopback 진단을 반복하지 않습니다. 결과가 또 모호하면 프로세스·네트워크 컴파트먼트 등을 별도 검토합니다. 12.10 FAIL·Stable BLOCKED 유지.

## 2026-10-10 01:27 ESTABLISHED endpoint 현장 결과 — 3개 루프백, 1개 미검출

- `Day12-Active-Connections-20261010-012751.json`: GSC fleet 검사 전후 동일, Wild/Playground/Lobby ONLINE, Other OFFLINE. 직전 네이티브 LISTEN에서 누락된 네 포트 **25571/25573/25575/25576 전부 localhost 연결 성공**.
- **25573 Lobby Java / 25575 Wild RCON / 25576 Playground RCON**: `Get-NetTCPConnection`과 .NET `IPGlobalProperties`가 각각 하나씩 `ESTABLISHED` 서버 측 로컬/원격 주소 `LOOPBACK` 관찰. **25571 Playground Java**: 접속은 성공했지만 서버 측 ESTABLISHED 행 0건, `Get-NetTCPConnection` 오류. `netstat`은 네 포트 모두 오류로 기록됨. 연결 직후 끊겼는지 등 원인은 미확인.
- 이 결과는 실제 통신 성공을 보강하지만 **오직 루프백에서만 LISTEN 중임을 보장하지 않음**. 정식 12.10 `backend_ports_private` PASS 금지. 무의미한 전체 재검사 대신, 향후 보고서에 민감정보 없는 구체적 오류 유형과 실제 LISTEN 주소 검증을 추가하는 쪽으로 조사. Golden, LAN, ACL, 8787, 이전 6/6 테스트를 반복하지 않음.

## 다음 한 번 (2026-10-10) — Windows LISTENER/ALL 제공자 비교

- 직전 검사에서 Java/RCON 6/6 로컬 연결 성공했고, ESTABLISHED 로그에서는 25573/25575/25576 서버 측 루프백 확인, 25571만 결과 없음. netstat 네 포트 모두 오류. 다만 오류 원인은 기록되지 않았습니다. **동일한 TCP 연결 검사 반복 금지.**
- 최신 Operator Kit의 `tools\\day12\\Day12_Phase10_Provider_Diff_READ_ONLY.cmd`를 **서버 PC 일반 권한으로 단 한 번** 실행합니다. Windows Native TCP TABLE `LISTENER`/`ALL` 차이, PowerShell `Get-NetTCPConnection` 필터 사용 여부에 따른 차이, netstat 종료 코드만 확인합니다. 서버·월드·방화벽·ACL·Golden·캐시 변경 및 TCP 연결 시도는 없습니다.
- 보고서 위치: 바탕화면 `Geumyi-Day12-Provider-Diff\\Day12-Provider-Diff-*.json`. 최신 파일 하나만 제출. `CAPTURED_REVIEW_REQUIRED`는 수집 성공일 뿐 보안 게이트 PASS가 아닙니다. 기존 `backend_ports_private` FAIL과 Stable 차단 유지.

## 2026-10-10 01:43 결과 — 12.10 새 IPv4 네이티브 표 교차검증 1회

- `Day12-Provider-Diff-20261010-014337.json`: 실서버 READ-ONLY 결과, `25571` (놀이터 Java) Windows Native IPv4 LISTENER 2종 **LOOPBACK 관측**, `25573`/`25575`/`25576`은 LISTEN 미관측. 같은 시점 Native ALL은 대상 0개, unfiltered CIM 0개, per-port CIM `NO_MATCHING_INSTANCE`, netstat 정상 종료 코드 0이지만 대상 0개. 원인을 앱 장애·공격·보안 정상 중 하나로 추정 확정하지 않습니다.
- 이미 온라인 Java/RCON 6/6 TCP 로컬 연결, 분리된 PC 내부 0/8 접근 불가, Golden 4/4 및 12.5 ACL/방화벽 증거를 확보했습니다. **반복하지 마세요.**
- 다음 단일 실행: 최신 Operator Kit의 `tools\\day12\\Day12_Phase10_TcpTable2_READ_ONLY.cmd`, **서버 PC 일반 권한**. Windows 공식 IPv4 `GetTcpTable2`로 온라인 Java/RCON 6포트의 LISTEN 주소 범위만 3차례 읽습니다. TCP 접속, 서버 재시작, API 호출, 월드/방화벽/백업 변경 없음. 바탕화면 `Geumyi-Day12-TcpTable2\\Day12-TcpTable2-*.json` 최신 하나만 제출하세요. **Windows 합성 CI 통과 이후** 실행합니다.
- 이 결과는 IPv4에 한정됩니다. 12.10 최종 검증과 외부 노출/IPv6/실게임 E2E는 별도입니다. 새 도구 결과만으로 `backend_ports_private`를 PASS로 바꾸거나 Stable을 배포하지 않습니다. 여전히 미확인이면 추가 단순 스캔을 멈추고 유지보수 창에 프로세스/리스너 설정을 직접 확인하는 설계 검토가 필요합니다.

## 2026-10-10 01:51 결과 — GetTcpTable2 0/6, 반복 스캔 중단

- `Day12-TcpTable2-20261010-015103.json`: **실서버** `GetTcpTable2` IPv4 표 조회 3/3 성공, 오류 없음, 대상 온라인 Java/RCON 포트 여섯 개 `25570/25571/25573/25575/25576/25579` 모두 **LISTEN 행 0개**. 네트워크 연결·설정 변경 없음. `0건`을 **포트 외부 노출이나 서비스 다운으로 단정 금지**; 기존 Native LISTENER(25570/25571/25579 loopback 관측), 6/6 localhost 연결, 서브 PC 0/8 내부 포트 불가와 측정 시점/방법이 다릅니다.
- 이 보고서의 마지막 해석 및 후속 결정: [`DAY12-PHASE10-BIND-DECISION-REPORT.md`](DAY12-PHASE10-BIND-DECISION-REPORT.md). **반복 READ-ONLY TCP 진단은 여기서 중단**합니다. 전체 12.10 `backend_ports_private`는 기존 최종 실기기 검증의 **18 PASS / 0 WARN / 1 FAIL** 유지입니다.
- 다음은 사용자가 별도 승인한 **유지보수 창 기반 실행 중 Java/RCON 프로세스 소유권·실제 bind 주소 검증**. 먼저 기존 증거/설정과 서비스 기동 경로를 읽기 전용으로 정리하고, 필요할 때만 승인된 한 서버로 범위를 제한한 제어 테스트를 계획합니다. 무단 서버 재부팅/종료, Windows 방화벽·ACL 변경, RCON 비밀번호/포트 변경, Golden 덮어쓰기, Stable 승격 금지. 별도 동의 전에 운영환경 변경하지 않습니다.
- 다음 단계는 12.10의 근거 확보와 12.5 안전 검토 마무리이며, 그 후 12.11 Live E2E → 12.12 soak → 12.13 Stable → Day1–12 전체 파일 정리입니다.

## 2026-10-10 서버 PC 실행 확인 — 12.10 다음 작업은 프로세스/설정 읽기 전용 확인

- 사용자 답변: **"서버컴"**. 01:51 `GetTcpTable2` JSON은 Java Minecraft 서버가 실제로 실행되는 Windows **서버 PC**에서 생성됐습니다. 검사 위치를 다시 물어볼 필요가 없습니다. 0/6 대상 LISTEN 미검출은 진짜 서버 측 관측 불일치이지만, **서비스 중단·외부 노출·안전 바인딩 확정 근거는 아닙니다**.
- 기존 01:19 로컬 Java/RCON **6/6 성공**, 01:12·01:43 일부 Native LISTEN 루프백 관측, 01:27 일부 ESTABLISHED 루프백, 서브 PC 내부 0/8 접근 불가는 이미 확보했으므로 재실행하지 않습니다.
- **다음 단일 READ-ONLY 진단:** 서버 PC에서 최신 Operator Kit의 `tools\\day12\\Day12_Phase10_Process_Bind_Preflight_READ_ONLY.cmd` 실행 → 바탕화면 `Geumyi-Day12-Process-Bind\\Day12-Process-Bind-*.json` 하나만 제출. GSC 설정에 있는 경로는 메모리에서만 활용하고 JSON에서는 서버별 `server-ip` 범위, Java/RCON 포트·활성 설정, Java 실행 종류·구성 파일 경로 문자열 일치 여부의 집계값만 기록합니다. 일반 권한, 재시작·TCP 포트 스캔·방화벽·백업 변경 없음.
- `Get-NetIPInterface -IncludeAllCompartments`는 Microsoft 문서상 네트워크 **인터페이스** 구획 조회이며 `Get-NetTCPConnection` 소켓의 소속 구획을 자동 확인하지 않습니다. 보고서의 디렉터리/명령줄 부분 문자열 일치는 약한 단서일 뿐 실제 바인딩 증명이 아닙니다. 그다음에도 실서비스 소켓 주소 확인이 필요하면 **별도 사용자 승인 하 유지보수 창**에서 시행합니다. 12.10 FAIL, Stable BLOCKED 유지.

## 2026-10-10 02:05 실서버 프로세스·설정 증거 접수 — 재검사 보류

- `Day12-Process-Bind-20261010-020508.json` 실서버 보고서 읽기전용 CAPTURED: 야생·놀이터·기타·로비 **4개 구성 파일 모두 server-ip=LOOPBACK_CONFIG**, 계획된 Java/RCON 포트 일치, RCON 활성화. 기타 서버는 앞선 Fleet에서 OFFLINE이었으며 설정 존재와 현재 실행은 구분합니다.
- Windows Java 프로세스는 **10개**, 실행 인수 읽기 **10개**, GSC 이름의 프로세스 **2개**. `kind=""` 집계는 프로세스 분류 자료형 처리 문제로 수정·Windows CI 합성 테스트 완료했지만 **실서버 분류를 재검증하지 않았음**. 서버 경로 인수 일치 0은 상대 경로 기반 시작 등의 가능성이 있어 즉시 오류로 간주하지 않음.
- OS 인터페이스 구획 1개, 비기본 구획 0개. 이것만으로 소켓 구획이나 실제 바인딩은 확정 불가. 정리 문서 `DAY12-PHASE10-BIND-DECISION-REPORT.md` 참조.
- **사용자는 이 보고서만을 위해 또 CMD를 실행할 필요 없음.** 반복 TCP/프로세스 스냅샷 중단. 다음은 GSC 실행 관리 소스와 Paper/RCON 바인딩 경로를 오프라인 코드 검토 후, 실제 서비스 중단이 반드시 필요할 때만 Golden 확인·유지보수 창·사용자 승인하 통제된 실서버 1대 점검. `backend_ports_private` FAIL, 12.10 OPEN, Stable BLOCKED 계속 유지.

## 2026-10-10 12.10 GSC 소스 분석 — 새 TCP 스캔 중단, 시작 로그의 주소만 확인

- GSC `getServerStatus`에서 ONLINE은 `tcpOpen("127.0.0.1", JavaPort)`로 판정합니다. 이는 TCP 로컬 접속 성공이지 바인딩 주소의 독점적 증명이 아닙니다. GSC `launchCommand`는 `start.bat`을 해당 서버 폴더에서 실행하므로 Java 실행 명령에 절대 경로가 빠질 수 있습니다. `rememberServerProcess`는 OS `GetExtendedTcpTable`의 포트 PID 행에 의존해 OS 조회가 누락되면 프로세스 확인에 실패할 수 있으나, 운영 장애 발생 여부는 별개입니다.
- 공식 소스 대조 보고서: `DAY12-PHASE10-GSC-SOURCE-AUDIT.md` (판단·한계·대안). 기존 02:05 파일 설정 검사는 정상. **추가 TCP 표/프로세스 분류 재검사는 하지 않습니다.**
- 다음 1회만 필요 시: **최신 Day12 Operator Kit**에서 서버 PC `tools\\day12\\Day12_Phase10_Startup_Log_Bind_READ_ONLY.cmd` 실행 → 바탕화면 `Geumyi-Day12-Startup-Bind\\Day12-Startup-Bind-*.json` 최신 하나 제출. `latest.log` 파일의 앞부분 최대 6MiB에서 Java/RCON 각각의 시작 시 수신 주소 안내문을 읽고 **루프백/와일드카드/기타**로 분류합니다. 로그 원문·비밀번호·닉네임·경로는 내보내지 않습니다. 서버 재시작이나 포트 접속 없음.
- **경계:** Paper 로그 형식이 달라 안내문이 없으면 `NO_STARTUP_BIND_MESSAGE`로 보고하며 이를 안전하다고 간주하지 않습니다. 로그가 수신 주소를 나타내도 실행 시점 증거일 뿐 현재 소켓 바인딩을 보증하지 않습니다. RCON과 Java는 독립적으로 검토합니다. 12.10 `backend_ports_private` FAIL 및 Stable 차단 유지. 다음 단계가 운영 환경 변경을 요구할 경우 따로 승인받습니다.

## 2026-10-10 02:20:13 애플리케이션 로그 확인: Java·RCON 8/8 시작 당시 루프백

- `Day12-Startup-Bind-20261010-022013.json` 실제 서버 PC, 읽기 전용, 4개 프로필 `latest.log` 각각의 **Java+RCON 시작 주소 LOOPBACK 8/8 검출**. 야생/놀이터 로그 마지막 기록 10.6분 전, 로비 60.3분 전, 기타 4123.9분 전(이전 Fleet OFFLINE)이므로 **시작 당시 기록이지 현재 전 서버 온라인·리스너 독점 바인딩 증명이 아닙니다**. 로그 4개 모두 스캔 절단 없음.
- 앞선 02:05 디스크 설정 4/4 loopback, localhost Java/RCON 6/6, 별도 PC 내부포트 LAN 0/8 불가 결과와 합치면 **정상 설계를 뒷받침하는 강한 다중 근거**를 확보했습니다. 현재 포트 노출을 확인한 증거는 없으나 **OS 런타임 리스너 모든 포트의 현재 bind+owner 확증은 미해결**입니다.
- 이 단계에서 **추가 CMD 실행 요구하지 않음**. Java와 RCON의 시작 로그는 별도 증거로 완료 처리하되 기존 정식 `backend_ports_private` FAIL/12.10 OPEN, Stable BLOCKED 유지. 동일 TCP 진단과 로그 검사 반복 금지.
- 다음은 assistant가 **GitHub의 12.11 E2E·12.12 soak 안전 준비**를 검토합니다. 실제 서버 중단·재시작·설정 변경이 필요한 경우에만 구체적 영향/백업/롤백을 알려 사용자 실행·승인을 받습니다.

## 2026-10-10 02:47 실서버 재시작 성공, OS 바인딩 미관측 — 같은 동작 반복 금지

- 서버 PC `Day12-Scoped-Restart-20261010-024734.json`: 놀이터 단독 `GSC_GRACEFUL_RESTART` 실제 수락→job=`completed`, 전후 ONLINE, 접속자 0명, 보호·검증 FULL 백업 확인, 작업 충돌 0, 업데이트 `current` / `block_start=false`. **정상 lifecycle 점검은 이번 1회로 완료**하되 게임 클라이언트 접속 테스트로 대체하지 않습니다.
- 재시작 직후 Windows 네이티브 LISTEN 검사 `CAPTURED`, Java **25571 미관측**, RCON **25576 미관측**. 외부 노출이 발견된 것이 아니라 **전용 루프백 LISTEN의 실시간 증거 확보 실패**입니다. 8/8 시작 로그와 4/4 Java 설정 등 기존 양호한 신호 유지.
- **같은 CMD 다시 실행하지 마세요.** 즉시 서버 재시작/강제 종료/복구/설정 수정 추가 금지. 기존 Golden 보존, Day12.10 `backend_ports_private` FAIL, Stable 차단.
- 어시스턴트 다음 작업: Windows 네이티브 리스너 수집기·GSC 자체 PID 조회의 공통 구현 및 실제 검증 게이트를 Microsoft API 문서 기준으로 정적 검토하고, 독립적/비파괴적인 실시간 검증 대안과 12.11·12.12 준비만 진행합니다. 원인 확정 또는 새로운 증거 계획 없이는 추가 유사 CMD를 요청하지 않습니다.

## 2026-10-10 — new 12.10 WFP historical audit evidence: one read-only capture

- Windows Safety CI `37977424905` **PASS**, WFP synthetic tests included; Day12 Operator Kit `37977424871` **PASS** (same source `6b436cf6c`). Neither result is a production security PASS.
- Use the **updated Operator Kit**, on the Minecraft server PC. Run `tools\day12\Day12_Phase10_WFP_Audit_Attestation_READ_ONLY.cmd` **once**. This reads existing Windows Security audit events **5154/5158**, not the previous network TCP table; may require administrator rights to *read Security events only*. No changes to auditing, firewall, TCP ports, services, worlds or Golden backups.
- Submit the newest `Desktop\Geumyi-Day12-WFP\Day12-WFP-Bind-*.json` file. Report contains **only service/port/scope categories and event counts**, not raw event XML, addresses, executable paths, PIDs or credentials.
- `UNAVAILABLE`/no matching events means missing historical evidence—not broken Minecraft, and not PASS. Do **not** enable `auditpol`, repeat stale TCP scans, blindly restart servers or switch to an unreviewed fallback. An event showing wildcard/nonloopback bind requires focused security investigation. Strict `backend_ports_private` stays **FAIL**.
- Reference: [WFP read-only plan](DAY12-PHASE10-WFP-READONLY-PLAN.md).

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


## 2026-10-10 — real SERVER-PC Day12.7 complete byte integrity (84/84) — NOT offline-start E2E

- **Received private real operator** `Day12-Cache-Integrity-READ-ONLY.json` from focused Windows tool (CI [`38013828430`](https://github.com/geumyi22/Geumyi-Minecraft-System/actions/runs/38013828430) success). Report `schema=1`, `phase=12.7-cached-bytes-integrity`, `synthetic=false`, `read_only=true`, `cache_modified=false`, `network_requests=0`, `manifest_valid=true`, `result=CACHED_BYTES_HASHES_MATCH`.
- **All 84/84 cached files verified SHA-256 and size** against the existing local manifest. `missing=0`, `mismatched_sha256=0`, `mismatched_size=0`, `invalid_record=0`, `duplicate_names=0`, `reparse_blocked=0`.
- Accepted scoped gate **`phase_12_7_cache_byte_integrity=PASS_REAL_HOST`**, while the *separate* mandatory **`phase_12_7_offline_known_good_startup=PENDING_LIVE`** remains OPEN. The local manifest hash check does not establish cryptographic trust of the manifest itself, GSC/Geyser/Paper boot with internet disconnected, automatic fallback, or runtime E2E.
- **No duplicate cache Build/Audit or hash check required.** Golden 4/4 remains protected, GSC Host 4.3.8 not touched, Java/Bedrock worlds not touched. Canonical `backend_ports_private=FAIL_UNVERIFIED_NATIVE_OWNER_ADDRESS`, 12.5 effective security OPEN, 12.11 live E2E and 12.12 soak OPEN, Stable/Maintenance BLOCKED.

## 2026-10-10 — quick-first order supersedes soak-first suggestion

The operator requested **shorter checks before the 8-hour soak**. Follow `DAY12-QUICK-FIRST-20261010.md`. Begin with non-disruptive GSCM Android+iOS status/reconnect and GSC console read-only `list`, then Java actual Lobby/routing/last-location checks. Keep 12.4 as no-action after zero cleanup candidates and preserve Golden backups. Do not create/launch an eight-hour monitor now, and do not repeat already accepted Bedrock pack/Velocity restarts. Day12.10 strict security and the broad 25-case E2E remain open.
