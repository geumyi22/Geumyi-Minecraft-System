# GSC 5.0.0 local maintenance candidate — 2026-11-08

> **운영 결과 업데이트 (2026-11-10 작성, 실컴 마지막 검증 2026-11-08):** 아래의 “local maintenance candidate” 문서는 **적용 전 기록**입니다. 이후 실제 PC에 적용·QA를 완료한 상태는 다음 장의 기록을 우선합니다. 최신 요약: [GSC 5.0 운영·GitHub 상태](https://github.com/geumyi22/Geumyi-Minecraft-System/blob/main/docs/operations/GSC-500-STATUS-2026-11-10.md).

## 적용 완료 및 최신 검증 결과 (2026-11-08)

- **정확한 소스/빌드:** `c39ecd6722fac0828377de553c1fa4e07286d933`; 실행 중인 Host/Client의 `build_revision=maintenance-c39ecd6722fac0828377de553c1fa4e07286d933` 일치. 공개 GSC 5.0.0 Stable의 설치 파일/서명과 **동일 바이너리가 아님**. `main` 및 서명 릴리스 자산 변경 없음.
- **빌드·회귀:** 해당 커밋의 [System CI 42480002536](https://github.com/geumyi22/Geumyi-Minecraft-System/actions/runs/42480002536)에서 18개 작업 성공, 로컬 `go test ./... -count=1` / `go vet ./...` 통과. Windows 온라인 월드 백업의 `session.lock` 잠금 오류는 실패 재현 테스트를 작성해 수정; 다른 월드 데이터 잠금은 계속 오류로 처리함.
- **실제 적용:** 외부 Staging 시간 초과·오류 기록·중복 요청 처리와 SHA-256 검증 보완. Geyser를 기존 Velocity 3개 프록시에 적용. NetherNet 건강 검사·롤백 검증·브라우저 외부 출처 차단 적용. 프록시·Paper·원래 작업 스케줄러 소유권을 보존.
- **AutoSaveWorld 상태:** 아래 과거 후보의 “remains installed”는 더 이상 현재 상태가 아님. 야생·놀이터·기타에서 JAR 3개를 로딩 경로 밖의 **복구 가능한 격리 백업**으로 이동. 기존 설정·백업은 보존; Paper 기본 자동 저장 6000틱 및 GSC 백업 기능 정상 확인.
- **백업 실제 검증:** 야생·놀이터·로비의 실제 ZIP/SHA256 백업 완료. 로비 백업을 별도 폴더에 추출해 91개 파일 및 `level.dat` 해시 검증 PASS. 실월드 복원 및 게임 재시작 E2E는 별도 미실행.
- **백업 빈도:** 2시간마다 12회/서버 설정으로 생성한 24개 예약 중 **20개는 비활성화**, 4개만 활성화. 야생 06:00·18:00, 놀이터 06:10·18:10. 대형 월드 백업(놀이터 회당 약 3.14GiB)이 누적되어 디스크를 소진하지 않도록 간격을 늘렸으며, 원래 예약과 기존 백업을 삭제하지 않음. GSC Trash는 디스크 공간을 즉시 회수하지 않으므로 용량 모니터링 필요. 새 시간표의 실제 정시 자동 실행은 아직 확인되지 않음.
- **서버·게임:** 백엔드 4개 모두 시작/RCON/`save-all flush` 테스트 PASS. 2026-11-08 마지막 상태는 야생·놀이터·로비 ONLINE, 기타는 원래의 의도적 OFFLINE. Java 상태 프로토콜/NetherNet 로컬 검사 PASS. 이후 **사용자가 실제 Minecraft 플레이 시 “플레이에서 모든 기능 다 잘된다”고 직접 확인**했으므로 운영자 확인 실플레이 PASS로 기록.
- **미완료 범위:** Java/Bedrock 각각의 로그인 증빙, 외부 WAN·모바일 GSCM, 멀티플레이 장시간 부하, 라이브 월드 복원, 재부팅 후 장시간 상태는 별도 미확인. 사용자 확인을 모든 종류의 E2E PASS로 확대하지 않음. OS TCP LISTEN 열거 이상은 원인 미확정으로 기록하고 반복 검사하지 않음.
- **사용자 결정:** 현재 GSC 5.0 주요 개발 종료, 필요 최소한의 안정화·유지보수로 운영. 원본 월드·플레이어 데이터·비밀 정보는 GitHub에 업로드하지 않음.

---

Scope: explicitly authorized preservation-first maintenance and play-readiness checks. Based on public tag `gsc-v5.0.0` / `cd25f677e3f6380892255fbd925666c8a1b9be77`. This branch is not the published Stable and does not change its tag, release assets, deployment manifest, main branch or formal release gates.

## Changes

- Separate the bounded two-minute external JAR transfer budget from the unchanged 20-second metadata timeout. Preserve HTTPS, trusted initial hosts, file-size cap and SHA-256 verification; reject HTTP redirect downgrade.
- Preserve cancelled/failed download cleanup. Refuse concurrent external staging and unknown component IDs. Use collision-resistant staging directory names and exclusive temporary files.
- Persist failed staging plans and per-component reasons, even when zero artifacts succeed. Empty plans cannot be applied; do not silently fall back to an older successful plan.
- Route external status/staging through the existing long-operation Client transport, retaining the short timeout for normal health/status requests.
- Prevent duplicate staging clicks, clear stale apply roots and retain existing UI layout and explicit apply confirmation.
- Optional `build_revision` identifies locally compiled Host/Client maintenance binaries. Public version compatibility remains 5.0.0; SHA-256 and build revision must distinguish these binaries from the signed public release. The existing installed Setup and public release remain unchanged.

## Tests performed before deployment

- Baseline Windows `go test ./...`: PASS.
- Modified Windows `go test ./...` and `go vet ./...`: PASS before final build-identity addition; rerun required after final changes.
- Regression coverage includes a delayed real TLS response body, successful SHA-256, short-budget timeout cleanup, cancelled downloads, corrupt payload rejection, untrusted initial host and HTTP downgrade rejection, failed-plan persistence, empty-plan apply rejection, duplicate/unknown stage requests, and a delayed reverse-proxy staging response.

## Operational safety

An offline byte-for-byte copy of the four server trees plus installed binaries, selected private configuration and proxy files was created locally before mutation. 11,351 copied files (19.07 GiB) passed SHA-256 readback. Private backup paths/configuration/tokens are not committed here. Original worlds and player data are not reset, pruned or replaced. AutoSaveWorld remains installed; its unsupported forced region-cache flush option is disabled separately, retaining save and backup settings. Existing Windows Scheduler ownership of Velocity remains unchanged.

## Evidence boundaries

Unit/integration tests do not prove authenticated Minecraft gameplay, remote/mobile E2E, long-duration soak, or production update rollback. Live deployment, staging, proxy/Paper startup, UI observations and protocol checks must be reported separately with observed results. The pre-existing Windows TCP listener enumeration anomaly is not claimed solved. No formal `FINAL-*` gate is changed by this candidate.

## Reviewed continuation after interrupted chat

- The first local candidate was installed with a distinct build revision. Actual Geyser staging subsequently succeeded (one verified artifact, no live modification). A later rolling apply hit the legacy RakNet-only health gate after Geyser migrated to NetherNet; this was not treated as successful apply.
- Add bounded loopback NetherNet `/v1/join` discovery validation alongside RakNet PONG. Neither establishes an authenticated Bedrock/WebRTC gameplay session.
- Back up proxy plugin configuration with the JAR, verify rollback bytes, and fail closed if the proxy does not stop or a restore fails. Preserve Floodgate keys and world data.
- Add browser-origin/host checks for the local Client and Host loopback exemption, preserving valid token-authenticated remote Client proxy requests. Native authentication semantics remain unchanged.
- Reviewed Windows `go test -count=1 ./...` and `go vet ./...`: PASS. These new source changes still require separate binary deployment and live checks.
- No feature removal, world reset, public Stable asset replacement, main merge or formal release-gate promotion is part of this local candidate.
