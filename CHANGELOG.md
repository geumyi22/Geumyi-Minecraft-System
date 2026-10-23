# Changelog

## 2026-10-20 — GSC 4.5.2 Velocity Host Staging confirmed (not installed)

- 서버 PC의 운영자 출력 `CANARY_STAGED_NO_INSTALL`: 이전 GSC Host 실행 파일 보호 백업, Canary SHA-256 검증, 세 개의 기존 Velocity 작업 보존 성공. `service_restarted=false`, `scheduled_tasks_changed=false`, `java_changed=false`. **서비스 교체·Canary 설치·프록시 중지/전환은 아직 실시하지 않음**.
- 다음 단일 단계: GSC 호스트 Windows 서비스 시작 구성·복구 파일·기존 프로세스·원본 스냅샷·고아 마커 **읽기 전용 사전 검증**. PR #57 개발 전용 스크립트와 CI; 사용자 환경에서 통과 확인 필요.

## 2026-10-20 — GSC 4.5.2 Velocity Canary 중간 GitHub 정리 (Draft, 미배포)

- [Draft PR #57](https://github.com/geumyi22/Geumyi-Minecraft-System/pull/57)의 직접 관리 Velocity 엔진, GSC 상태·시작·정상 종료·재시작 UI/API, 원본 예약 작업 보호 스냅샷, 승인형 전환·롤백, 중복 JVM 방지 기록을 현재 개발 대상으로 정리했습니다. 해당 실행은 기본 잠금 상태이며 실제 서버 적용·배포를 의미하지 않습니다.
- 운영자가 야생·놀이터·기타 3개 예약 작업의 실행 설정·JAR SHA를 읽기 전용으로 확인하고, **원본 작업 3개 SNAPSHOT_ONLY 백업 성공(변경 0건)**을 보고했습니다. 현재 세 작업은 기존 Scheduler 실행 기준으로만 확인됐으며, Canary stage-only 결과와 실서버 전환은 미확인입니다.
- GitHub 격리 Windows CI는 공식 Velocity 4.2.0 프로세스 콘솔 정상 종료/재시작, fake Scheduler 작업 전환·원복, Host EXE 자체 테스트 및 Go/Race 검사를 통과했습니다. [System CI](https://github.com/geumyi22/Geumyi-Minecraft-System/actions/runs/39441217776). 실운영 Java/Bedrock 접속이나 GSC 호스트 중단 후 고아 프로세스 자동 복구까지 통과했다는 뜻은 아닙니다.
- [최신 단일 작업 현황](docs/operations/GSC-452-VELOCITY-CURRENT-STATUS-2026-10-20.md)과 [열린 PR 역할 정리](docs/operations/PR-TRIAGE-2026-10-20.md)를 문서화하고 README/운영 인덱스/로드맵/버전표에 연결했습니다. `main`, 기존 Stable·Beta 릴리즈, 서버 PC, Paper 월드, 운영 설정은 변경하지 않았습니다.


## 2026-10-11 — GSC 4.5.1 / GSCM 1.5.1+151 Latest Stable (수동 설치판)

- [최신 Stable 패키지](https://github.com/geumyi22/Geumyi-Minecraft-System/releases/tag/system-2026.10.11-stable-gsc451-gscm151) 공개: Windows Setup/Host/Client, Android 영구 릴리즈 서명 APK, iOS 미서명 IPA, SHA-256·provenance 총 10개 파일.
- GSC에서 ViaVersion/ViaBackwards의 SHA-256 Staging과 **별도 오프라인 적용**을 구분하고 등록된 backend 정지 확인, 백업·교체 중 오류 복원 절차를 추가. 서버 재기동 후 health/E2E 검증은 별도.
- GSCM 설정의 앱 실행 시 업데이트 버전 확인(해제 가능), 수동 확인, GitHub 릴리즈 링크 추가. Android 자동 설치 및 iOS 미서명 IPA 설치는 지원하지 않음.
- [원본 빌드 CI](https://github.com/geumyi22/Geumyi-Minecraft-System/actions/runs/38084637534)의 구성요소 검사와 해시 검증은 통과했으나 GitHub 초안 태그 조회 404로 최초 publish 실패; [ID 기반 공개 CI](https://github.com/geumyi22/Geumyi-Minecraft-System/actions/runs/38085210886)는 SUCCESS.
- 서명된 `deployment-stable.json`과 정식 보안 게이트는 그대로 유지(자동배포 승인 미완료). 운영 PC/월드/Golden 백업 변경 없음. 마지막 운영 실기기 확인 버전: 4.3.8/1.1.5+117.

## 2026-10-11 — GSC 4.5.0 / GSCM 1.5.0+150 수동 설치 Stable 공개
- [최신 패키지 릴리즈](https://github.com/geumyi22/Geumyi-Minecraft-System/releases/tag/system-2026.10.11-stable-gsc450-gscm150): Windows GSC Setup/Host/Client, Android 서명 APK, iOS 미서명 IPA 및 체크섬·출처 기록 등 10개 등록.
- [원본 빌드](https://github.com/geumyi22/Geumyi-Minecraft-System/actions/runs/38081642958)의 테스트/해시 검증은 통과. 게시 단계의 오류는 [후속 게시 검증](https://github.com/geumyi22/Geumyi-Minecraft-System/actions/runs/38082558818) SUCCESS로 마무리.
- Day 12의 소규모 운영 기준 마감과 정식 서명 자동배포 보안 승인 차단을 명확히 구분. 사용자 운영 기기나 백업은 변경하지 않음.
- 일회성 릴리즈 워크플로를 보관하고 사용하지 않는 활성 정의를 제거함.

## 2026-10-07 — Day 11 closure

- Promoted the verified Day-11 runtime baseline to **GSC 4.3.8** and **GSCM 1.1.5+117**.
- Recorded successful Client-only and Host 4.3.7 -> 4.3.8 self-update paths.
- Phase 11.7 Protection & Recovery 2.0 live read-only and disposable-backup lifecycle checks passed.
- Final integrated Day-11 READ-ONLY E2E passed with no mutation and no API/check failures.
- User confirmed Java and Bedrock post-update real-client smoke tests passed.
- User confirmed both remaining requested GSCM build117 device checks passed.
- Marked **Day 11 COMPLETE** and moved Day 12 to ready-to-start state.
- Repository cleanup removed two unreferenced root-level GSC 4.3.0 metadata/document copies; historical recovery/HOTFIX evidence was intentionally retained.


## 2026-10-04 — Day 10 Bedrock closure

- User confirmed real Bedrock client operation on the Day-10 Velocity/Geyser/Lobby network.
- Day 10 is now **COMPLETE**: Java and Bedrock client paths are both treated as passed by user verification.
- The earlier `SKIPPED_UPSTREAM_UNSUPPORTED` record is retained as historical evidence for the first skipped Bedrock test; it no longer represents current completion status.
- No assistant-side client execution is claimed.

## 2026-10-04 — Canonical Day timeline / roadmap cleanup

- Added `DAY-TIMELINE.md` as the single source of truth for Day numbering and completion state.
- Clarified Day 4 as a real verification/closure milestone with no new implementation; later Day numbers are not shifted.
- Canonically marked Day 8 and Day 9 as **completed**. Their E2E PASS results are completion evidence, not partial-state labels.
- Kept Day 10 Java four-server/Lobby/routing/reboot verification complete while leaving the real Bedrock client E2E pending.
- Changed the current Day-10 closure rule from a permanent "wait for upstream" condition to **actual Bedrock client E2E required**; the original `SKIPPED_UPSTREAM_UNSUPPORTED` value remains historical evidence.
- Fixed roadmap drift across README, ROADMAP, VERSION-MATRIX, Day-10 plan/report, Network docs and deployment architecture.
- Fixed the Day 11 target scope to **GSC 4.3 / GSCM 1.1.5**: Update Center/fleet UX, startup update checks, managed Geyser/Floodgate/Via policy, player-aware restart/update and RCON/intentional-stop state fixes.
- Fixed Day 12 as Extended Automation & Production Hardening: Resource/DataPack deployment, StatusAgent/extended self-update, SBOM/provenance/security scans, reproducibility, shared cache, offline hardening and DR drill.
- Documentation-only cleanup; no runtime component is claimed updated or re-verified by this entry.

## 2026-10-03 — Day 10 four-server Java cutover

- Deployed three isolated Velocity proxy instances for Wild, Playground and Other public aliases, all routing first to Lobby.
- Moved Paper backends to private Java ports `25570/25571/25572/25573` and kept public Java on `25565/25566/25567`.
- Added/verified GeumyiNetwork and GeumyiLobby routing, physical Lobby gates, `/lobby`, and per-server last-position restoration.
- Hardened live cutover rollback for interrupted recovery, UTF-8 config safety, RCON fallback and exact proxy-process cleanup.
- Verified after a real Windows reboot that all three Velocity startup tasks are Running, public Java ports are LISTEN, and Geyser UDP ports `19132/19133/19134` are BOUND.
- User-confirmed Java E2E PASS: public join -> Lobby, Lobby -> Wild/Playground/Other, `/lobby`, and last-location restore.
- Bedrock client E2E is recorded as `SKIPPED_UPSTREAM_UNSUPPORTED` because the current latest Geyser does not yet support the current Bedrock client version. Bedrock client verification remains pending; this is not recorded as a Bedrock PASS.
- Exact validation baseline for the final recovery-safe cutover source: `0e1490bfe75975eb278526df0f89a430109e28d8`; Day10 Hotfix CI `37113499045` and System CI `37113499031` both succeeded.

## 2026-09-29 — Day 8 secure release / updater foundation

- Added signed Day-8 Secure Release workflow with Stable/Beta/Canary channels, SHA-256 verification and Ed25519 deployment manifests.
- Added persistent Android release-signing path and GSC pre-start updater with fail-open behavior.
- Added GSC Update Center first-stage UI/API and one-run local/server E2E finalizer.
- Bumped GeumyiTechnology to **0.1.4** as a metadata-only Wild updater E2E marker; gameplay logic remains the recovered/verified 0.1.3 baseline.
- Added/updated Day-8 operator documentation.
- Published and verified signed canary Release `system-2026.09.29-222513-canary` via Secure Release run `36574955584`.
- Completed the server-PC Day-8 finalizer with user-confirmed `DAY 8 RESUME FINALIZER: PASS`: Wild Technology 0.1.4 applied/current and Playground isolation verified.
- Hardened the Windows finalizer during live E2E: ASCII/no-BOM CMD launcher, correct post-login auth verification, JDK keytool discovery, always-visible failure logs, and installer-process-only waiting with safe Release resume.
- **Day 8 closed.** Transaction journal, post-start health gate, automatic rollback and failure injection move to Day 9.

## 2026-09-27 — Recovery completion and Day-4 verification

- Completed GST 1.1.1 HOTFIX, StatusAgent 0.5.4, GeumyiTechnology 0.1.3 and GeumyiChemistry 0.4.1 source recovery/reconstruction tracking.
- Captured sanitized live Wild/Playground server configuration evidence and completed Day-4 E2E verification.
- Kept runtime binaries in GitHub Releases rather than the source tree.
- Removed the unused `release-source.example.txt`; the release workflow uses the explicit `source_url` input plus `release-tag.txt` / `release-sha256.txt`.

## 2026-09-26 — Source recovery

- Expanded GSC 4.2.3, partial Agent 0.5.4, GSCM 1.1.2+112 and GDS 1.1.1 into their component directories.
- Expanded current Wild/Playground Java and Bedrock resource packs with original asset bytes.
- Replaced GSCM base64 archive with the real source tree; retained existing build steps and Android compatibility settings. Corrected iOS artifact label to 1.1.2.
- Recorded missing exact GST HOTFIX, Technology, Chemistry, Agent helper and server configuration sources explicitly.
- Excluded bundled executables/JARs/APKs/IPAs, old source/docs, missing-script launchers, runtime state and packaging duplicates.
- Replaced the private-looking QR-test address with a synthetic example; retained blank/placeholder-only configuration templates.
- Left existing release assets unchanged.
