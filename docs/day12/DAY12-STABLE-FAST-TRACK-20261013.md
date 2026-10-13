# Day12 — Stable Fast Track (2026-10-13)

> **Review/Preparation Only — no live mutation or release approval.** This plan does **not** supersede `FINAL-RELEASE-GATES.json`, `tools/day12/validate_final_release_gates.py`, or `tools/day12/validate_final_closure_evidence.py`. Every undecided mandatory gate remains fail-closed.


> **2026-10-13 운영자 최신 결정:** Other Paper는 **의도적으로 OFFLINE**입니다. 따라서 12.10 검증에서는 실시간 운영 인스턴스만의 Java/RCON 바인딩·PID를 엄격히 확인하되, **OFFLINE Other의 백엔드 리스너 행이 없다는 것만으로 장애나 실패로 판정하지 않습니다.** Velocity의 공개 25567 프런트엔드가 여전히 열려 있을 수 있으며 이는 Other Paper가 ONLINE이라는 증거가 아닙니다. 2026-10-13 운영자는 **8시간 실호스트 계측을 포함한 완료 작업을 재승인**했습니다. 단순 수락으로 검사를 생략하거나 실제 실행 없이 PASS 처리하지 않습니다. [상세 진행표](../PROJECT-DAY1-12-MASTER-STATUS-20261013.md).

## Decision that avoids unnecessary rework

**2026-10-13 실서버 계측 후속:** [Day12.12 실제 8시간 모니터링 보고](phases/phase-12/DAY12-PHASE12-INSTRUMENTED-LIVE-SOAK-20261013.md). 기간 **8시간**, 샘플 **97개**, 최대 간격 **5분**, 프로세스 식별 교체·TCP 이상·수집 오류 **0**. **기존 ZIP 결과도 사용 가능**하며 Other Paper는 의도적 OFFLINE; Velocity 25567은 백엔드가 아니라 프록시 전면 포트입니다. `PASS_REAL_HOST_INSTRUMENTED_8H_TCP_PROCESS_SCOPE`로 인정하되 원본 `result=REVIEW_REQUIRED`와 나머지 필수 Stable 게이트는 변경하지 않습니다. **반복 8시간 모니터는 요청하지 않습니다.**

**Manual installer Stable ALREADY EXISTS** as GitHub Release [`system-2026.10.11-stable-gsc451-gscm151`](https://github.com/geumyi22/Geumyi-Minecraft-System/releases/tag/system-2026.10.11-stable-gsc451-gscm151), publicly published 2026-10-11 KST (tag commit `06bfbe53c53d966331834ecd8301f4764df60679`, 10 release assets). It packages **GSC 4.5.1 / GSCM 1.5.1+151**. GSCM iOS artifact is **unsigned**. This is **not** the Day12 mandatory-gated final automatically signed Stable. It does not include unmerged Draft PR #53 (`integration/day12-security-review-20261012`); no claim is made that its new security changes were deployed.

The historically last **live-confirmed** runtime baseline was GSC **4.3.8 / GSCM 1.1.5+117**, per `FINAL-BASELINE.json` and README. The 4.5.1 / 1.5.1 package exists, but current operator-host installed versions / updated iOS device compatibility are *not independently proven*. Do not confuse package availability, installation, and running build identity.

## Prior accepted scopes — do NOT request repeats

| Item | Evidence and accepted scope | Do not claim |
| --- | --- | --- |
| 12.0 Golden | 4/4 full Golden protected, operator evidence 2026-10-09 | Full current restore proof |
| 12.1 / gameplay | Operator accepts current Java/Bedrock/GSC/GSCM functions and pack behavior | New candidate live E2E |
| 12.2 provenance | 13/13 historical installed JAR hashes mapped to known CI/release sources | Currently loaded JAR versions |
| 12.4 storage | Actual dry-run had 0 eligible; user accepted NO ACTION | New retention policy applied |
| 12.7 cache | 84/84 file size + SHA256 matched manifest | Actual offline startup |
| 12.8 DR | Disposable/synthetic recovery CI green | Production data restored |
| 12.9 UX | Desktop & Android console observed; iOS patched-console operator-assumed | Installed updated iOS proof |
| 12.11 routine | 16 of 18 scoped items accepted; #12 disposable recovery CI evidence separate | Canary #17 actual apply/rollback |
| 12.12 soak | Owner accepted continuous problem-free operation | Formal timestamped 8h telemetry |
| PR #53 | 5/5 CI green at previously reviewed HEAD `3e6d411`; review still Draft | Host deployment, signed final release |
| ACL 6 candidates | Host read-only 14,304 object scan: six protected files, Allow-write trustees limited to SYSTEM/Administrators category | Actual effective access of other users |
| ACL live standard-user test | Host lacks a separate standard-user account; real probe reported `BLOCKED_FULL_OR_UAC_FILTERED_ADMIN_TOKEN`; no directory checked | A standard-user denial PASS |

Do not create a Windows account just to turn an UNVERIFIED result into PASS. Never change permissions merely to satisfy a report.

## Four engineering blockers to a *new* final automatically signed Stable

> **2026-10-13 22:58 KST 신규 실제 증거:** [12.10 Native listener owner/bind 보고서](phases/phase-10/DAY12-PHASE10-LIVE-OWNER-BIND-20261013.md). Wild/Playground/Lobby 실서버 Java+RCON **3쌍/6포트** Native IPv4 루프백·Paper 소유권 매칭, 상태값 0 호환 수정 효과 확인, 오류 코드 0; IPv6 owner provider는 수집 정상·대상 매칭 0; Other OFFLINE 2포트 이상 리스너 0. **이 실측 스코프는 PASS**로 기록하고 같은 TCP 진단을 다시 요청하지 않습니다. 단, 최종 `backend_ports_private` 게이트는 방화벽·WFP 전체 실효 정책 등 별도 안전성 판단 전 FAIL-CLOSED 유지합니다. 이제 12.7→12.11→12.5 준비를 우선합니다.


1. **12.5 runtime security — OPEN**: GSC root inherited broad-group WRITE Allow ACE; six protected files are not the root. Actual standard-user write denial, effective firewall review, backup-equivalent security descriptors and service operation remain unverified. No unrestricted ACL Apply and no auto-acceptance of inherited rights. With no actual standard user account, record **BLOCKED_UNVERIFIED**. A thoroughly justified, independently reviewed alternative security claim would require a separately approved policy amendment; never silently set PASS.
2. **12.10 private backend bind + PID — FAIL**: native OS IPv4/IPv6 OWNER_PID evidence not yet authoritative for **currently ONLINE managed Paper backends** and their Java/RCON endpoints. Historic app-startup loopback 8/8, online host subset 6/6 and LAN/Tailnet IPv4/IPv6 remote 0/8 do **not** establish contemporaneous all-eight OS bind. Other had been OFFLINE in the relevant snapshot; do not force eight rows from an offline server. Windows TCP state-0 anomaly has a documented source-specific fix; do not repeat equivalent Netstat/GetTcpTable2 scans without a changed proof technique.
3. **12.7 real offline known-good boot — OPEN**: test an actual safe isolated update-source outage, known-good cache fallback and service startup/health with rollback, without deliberately disrupting active players or bypassing an interrupted-update transaction block. Existing 84/84 cache and disposable GSC+Paper tests are accepted and need not be repeated.
4. **12.11 signed Canary #17 staged apply/rollback + final release E2E — OPEN**: actual signed test candidate/recoverable rollback is not proven on an approved host/staging environment. Preserve accepted 16/18 functional items and successful disposable crash recovery. Do not intentionally crash production or overwrite protected worlds for a test.

**Also blocking canonical release**: formal 12.12 time/health evidence (owner's earlier uninstrumented acceptance remains recognized; **the 2026-10-13 newly approved real 8-hour monitoring is now requested and pending an actual operator-host JSON**), current-candidate on-device/host identity where relevant, and finalized `FINAL-HEALTH-REPORT.json`, `FINAL-SECURITY-REPORT.json`, `FINAL-SOAK-REPORT.json`, `FINAL-E2E-REPORT.md` plus every required `FINAL-RELEASE-GATES.json` key. All are still pending; the release validator will reject a merely relabeled PASS.

## One maintenance-window workflow — requires explicit operator approval BEFORE execution

**Preparation, repo-only (allowed now):** keep PR #53 Draft, review integration/auth/access checks, gather safe current artifact hashes, prepare staged binary/checkpoint and an exact rollback procedure. Do not merge the PR. Existing manual Stable can stay published.

**Preflight on operator PC (now authorized in principle by the operator; actual login/tool execution remains required):** check players=0, active jobs=0, protected Golden 4/4 still available, rollback assets and free space. Determine current installed GSC/GSCM/Host versions and current network safety observations **without passwords, paths or PIDs in shared output**. Do not restart just to collect a redundant report.

**Controlled supervised staging (separate authorization):**
- Stage the *candidate* with known-good restore, without replacing production first.
- Prove signed canary apply/rollback (#17) and an offline-update-source fallback (#12.7) against a disposable or otherwise explicitly approved staging target.
- For 12.10, **do not start Other solely to manufacture an 8/8 result**. Keep its intentional OFFLINE expectation distinct from public Velocity 25567. Collect **one authoritative owner+bind result** for each currently ONLINE managed backend's Java/RCON pair using a proven OS owner/PID + IPv4/IPv6 method. If a future approved session starts Other, expand the evidence to that backend then; offline endpoints are NOT fabricated PASS. Abort on ambiguous owner/bind.
- Handle 12.5 ACL/firewall separately under an explicit **object-scoped** change plan and rollback only if justified. Service identity, real access token or accepted alternative security criterion must be reviewed before changing anything. A server startup does not implicitly approve an ACL/firewall update.
- Confirm post-check health, Java/Bedrock proxy, GSC Host/Client and GSCM critical operation in **one coordinated E2E**, avoiding already accepted repetitive game checks.

**Release decision (separate approval):** only after the real evidence is independently verified and all strict JSON/closure gates legitimately PASS, approve PR merge and a **new unique immutable final-release tag**. Run `.github/workflows/day12-final-release.yml`, with required signing credentials and artifact/checksum verification. It signs the deployment manifest and Android release; iOS output remains unsigned, so do not describe it as installable iOS-signed Stable.

**Abort and rollback:** if any unexpected host/service/port/ACL change, player activity, failed integrity/rollback preflight, missing real privilege evidence or network bind ambiguity occurs, stop without promotion. Restore **only the explicitly authorized staging changes** by preverified recovery instructions; do not use Golden world restore by default. Preserve the current stable manual release and original service.

## Exact review status at this file creation

- **Existing manual GSC 4.5.1/GSCM 1.5.1 Stable:** PUBLISHED; not falsely republished.
- **Final signed Day12 Stable:** BLOCKED, by mandatory live/closure gates.
- **PR #53:** Draft, unmerged, not present in the already published Stable tag.
- **Next required decision:** a single explicit maintenance/test authorization covering exact on-host operations and rollback *once the candidate and evidence plan is ready*. No permission is inferred from general “진행” or “고고”.
- **Do not do:** more admin-token-as-standard-user checks, repeated existing Java/Bedrock pack smoke, another 84-file hash run, blind TCP scans, or a **second redundant soak after the authorized eight-hour instrumented run**.
