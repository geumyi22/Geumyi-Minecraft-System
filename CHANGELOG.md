# Changelog

## 2026-11-18 — GitHub 문서 정리 및 5.1.2 후보 상태 구분

- [저장소 전체 점검](docs/operations/GMS-GITHUB-AUDIT-2026-11-18.md)에서 `main` Git 트리의 파일 1,731개와 브랜치 29개, 열린 개발 PR 13개를 확인하고, 명백한 임시/캐시 추적 파일이 없음을 기록했습니다. 복구/릴리스 근거를 임의로 삭제하지 않았습니다.
- README·문서 목차·GSC 구성 안내에서 서로 모순되던 “최신” 표기를 현재 **GSC 5.1.1 개인용 Stable**로 통일하고, 4.x/5.0/5.1.0 기록은 날짜별 이력으로 남겼습니다.
- [5.1.2 콘솔 개선 추적 Issue #66](https://github.com/geumyi22/Geumyi-Minecraft-System/issues/66) 생성. [후보 브랜치](https://github.com/geumyi22/Geumyi-Minecraft-System/tree/feature/velocity-console-20261115)의 [CI 성공 #43672360070](https://github.com/geumyi22/Geumyi-Minecraft-System/actions/runs/43672360070)은 **소스 검토용 ZIP 내보내기**만 확인했으며 콘솔 제어 코드·실제 플레이 E2E 성공이 아님.
- 이번 작업은 **GitHub 문서·개발 추적·Git 무시 규칙 정리**이며 Stable 태그·바이너리·서명/월드·실운영 PC는 변경하지 않았습니다.

## 2026-11-15 — GSC 5.1.1 개인용 Stable (설치 업그레이드 오류 수정)

- [GSC 5.1.1 공개 릴리스](https://github.com/geumyi22/Geumyi-Minecraft-System/releases/tag/gsc-v5.1.1) — 5.0.0 Host 정상 Health인데 5.1.0 설치기가 버전 이전을 허용하지 않던 오류 수정.
- Host 중지·불일치·알 수 없는 버전은 계속 차단하며, [Windows CI·서명 릴리스 게이트 21/21 성공](https://github.com/geumyi22/Geumyi-Minecraft-System/actions/runs/43623012808) 확인. [상세 QA 및 운영 주의사항](docs/operations/GSC-511-MIGRATION-HOTFIX-2026-11-15.md).
- 새 공개 릴리스의 게시와 **실제 운영 PC에 설치·플레이 완료**는 구분. 공개 5.0.0/5.1.0 자산 보존.

## 2026-11-15 — GSC 5.1.0 개인용 Stable (서버 7종 및 새 Velocity)

- [GSC 5.1.0 공개 릴리스](https://github.com/geumyi22/Geumyi-Minecraft-System/releases/tag/gsc-v5.1.0) — 새 Paper/Spigot/Purpur/Vanilla/Fabric/Forge/NeoForge 관리와 신규 GSC 소유 Velocity 제어.
- [정확한 CI 21/21 성공](https://github.com/geumyi22/Geumyi-Minecraft-System/actions/runs/43619416741). 기존 Windows Scheduled Tasks 소유 Velocity 세 프록시를 강제로 전환하거나 운영 PC에서 새 버전을 검증한 것은 아님.

## 2026-11-08 — GSC 5.0.0 개인용 Stable 및 로컬 유지보수

- [GSC 5.0.0 공개 릴리스](https://github.com/geumyi22/Geumyi-Minecraft-System/releases/tag/gsc-v5.0.0), 정확한 소스·서명 기록 보존.
- 별도 로컬 유지보수 빌드에서 실제 사용자 Minecraft 플레이 정상 확인, Geyser Staging·백업·NetherNet 검증. `main` 소스와 공개 파일을 혼동하지 않음. [운영 검증 범위](docs/operations/GSC-500-STATUS-2026-11-10.md).

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
