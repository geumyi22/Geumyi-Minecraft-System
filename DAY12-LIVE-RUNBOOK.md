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
