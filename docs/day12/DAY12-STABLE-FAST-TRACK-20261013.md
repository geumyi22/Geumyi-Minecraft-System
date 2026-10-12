# Day12 — Stable Fast Track (2026-10-13)

> **Review/Preparation Only — no live mutation or release approval.** This plan does **not** supersede `FINAL-RELEASE-GATES.json`, `tools/day12/validate_final_release_gates.py`, or `tools/day12/validate_final_closure_evidence.py`. Every undecided mandatory gate remains fail-closed.

## Decision that avoids unnecessary rework

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

1. **12.5 runtime security — OPEN**: GSC root inherited broad-group WRITE Allow ACE; six protected files are not the root. Actual standard-user write denial, effective firewall review, backup-equivalent security descriptors and service operation remain unverified. No unrestricted ACL Apply and no auto-acceptance of inherited rights. With no actual standard user account, record **BLOCKED_UNVERIFIED**. A thoroughly justified, independently reviewed alternative security claim would require a separately approved policy amendment; never silently set PASS.
2. **12.10 private backend bind + PID — FAIL**: native OS IPv4/IPv6 OWNER_PID evidence not yet authoritative for all eight Java/RCON endpoints. Historic app-startup loopback 8/8, online host subset 6/6 and LAN/Tailnet IPv4/IPv6 remote 0/8 do **not** establish contemporaneous all-eight OS bind. Other had been OFFLINE in the relevant snapshot; do not force eight rows from an offline server. Windows TCP state-0 anomaly has a documented source-specific fix; do not repeat equivalent Netstat/GetTcpTable2 scans without a changed proof technique.
3. **12.7 real offline known-good boot — OPEN**: test an actual safe isolated update-source outage, known-good cache fallback and service startup/health with rollback, without deliberately disrupting active players or bypassing an interrupted-update transaction block. Existing 84/84 cache and disposable GSC+Paper tests are accepted and need not be repeated.
4. **12.11 signed Canary #17 staged apply/rollback + final release E2E — OPEN**: actual signed test candidate/recoverable rollback is not proven on an approved host/staging environment. Preserve accepted 16/18 functional items and successful disposable crash recovery. Do not intentionally crash production or overwrite protected worlds for a test.

**Also blocking canonical release**: formal 12.12 time/health evidence (owner's uninstrumented acceptance remains recognized, do not demand redoing an eight-hour routine run without necessity), current-candidate on-device/host identity where relevant, and finalized `FINAL-HEALTH-REPORT.json`, `FINAL-SECURITY-REPORT.json`, `FINAL-SOAK-REPORT.json`, `FINAL-E2E-REPORT.md` plus every required `FINAL-RELEASE-GATES.json` key. All are still pending; the release validator will reject a merely relabeled PASS.

## One maintenance-window workflow — requires explicit operator approval BEFORE execution

**Preparation, repo-only (allowed now):** keep PR #53 Draft, review integration/auth/access checks, gather safe current artifact hashes, prepare staged binary/checkpoint and an exact rollback procedure. Do not merge the PR. Existing manual Stable can stay published.

**Preflight on operator PC (not yet authorized):** check players=0, active jobs=0, protected Golden 4/4 still available, rollback assets and free space. Determine current installed GSC/GSCM/Host versions and current network safety observations **without passwords, paths or PIDs in shared output**. Do not restart just to collect a redundant report.

**Controlled supervised staging (separate authorization):**
- Stage the *candidate* with known-good restore, without replacing production first.
- Prove signed canary apply/rollback (#17) and an offline-update-source fallback (#12.7) against a disposable or otherwise explicitly approved staging target.
- For 12.10, if an approved quiet maintenance window starts all four profiles, collect **one authoritative owner+bind result** for all eight current Java/RCON endpoints from a proved kernel/API approach (IPv4+IPv6). Abort if listener ownership is ambiguous; do not claim 8/8 when Other is offline.
- Handle 12.5 ACL/firewall separately under an explicit **object-scoped** change plan and rollback only if justified. Service identity, real access token or accepted alternative security criterion must be reviewed before changing anything. A server startup does not implicitly approve an ACL/firewall update.
- Confirm post-check health, Java/Bedrock proxy, GSC Host/Client and GSCM critical operation in **one coordinated E2E**, avoiding already accepted repetitive game checks.

**Release decision (separate approval):** only after the real evidence is independently verified and all strict JSON/closure gates legitimately PASS, approve PR merge and a **new unique immutable final-release tag**. Run `.github/workflows/day12-final-release.yml`, with required signing credentials and artifact/checksum verification. It signs the deployment manifest and Android release; iOS output remains unsigned, so do not describe it as installable iOS-signed Stable.

**Abort and rollback:** if any unexpected host/service/port/ACL change, player activity, failed integrity/rollback preflight, missing real privilege evidence or network bind ambiguity occurs, stop without promotion. Restore **only the explicitly authorized staging changes** by preverified recovery instructions; do not use Golden world restore by default. Preserve the current stable manual release and original service.

## Exact review status at this file creation

- **Existing manual GSC 4.5.1/GSCM 1.5.1 Stable:** PUBLISHED; not falsely republished.
- **Final signed Day12 Stable:** BLOCKED, by mandatory live/closure gates.
- **PR #53:** Draft, unmerged, not present in the already published Stable tag.
- **Next required decision:** a single explicit maintenance/test authorization covering exact on-host operations and rollback *once the candidate and evidence plan is ready*. No permission is inferred from general “진행” or “고고”.
- **Do not do:** more admin-token-as-standard-user checks, repeated existing Java/Bedrock pack smoke, another 84-file hash run, blind TCP scans, or an unnecessary overnight soak.
