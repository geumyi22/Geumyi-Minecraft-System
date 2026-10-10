# Day 12 — Final Production Hardening & Closure

Status: **IN PROGRESS — repository/CI hardening toolchain verified; real server-PC/client closure gates pending**
Role: **final project milestone before Maintenance Mode**

Day 12 is not a feature-dump. Its purpose is to leave Geumyi Minecraft System in a state where normal operation no longer depends on manual file copying or frequent development work.

## Operator functional acceptance vs release verification — 2026-10-11

The operator states all game/GSC/GSCM features appear normal, explicitly accepts the three detailed Bedrock content checks, and requests no further drip-fed routine function checks. See `DAY12-OPERATOR-FUNCTIONAL-ACCEPTANCE-20261011.md`. GSCM iOS patched-console behavior is operator-asserted, **not** separately proven with an updated iOS binary/device log. Historical successful Java/GSC/Android and Bedrock checks remain accepted in their exact scopes.

**Do not auto-pass unexecuted 25-case tests** from this broad statement. The strict 12.10 backend privacy gate remains FAIL; actual 12.7 offline start and 12.12 eight-hour soak are untested, so Stable/Maintenance remain blocked. Stop repeated routine test requests; prioritize safe source/CI work and only ask for indispensable, separately approved real host safety operations.

## 2026-10-11 — Requested immediate review sequence 12.4 → 12.9 → 12.2 → 12.6

- **12.4:** previous real cleanup dry-run yielded zero eligible candidates; operator-approved **NO ACTION**, Golden 4/4 kept; retention policy not applied or scheduled. `DAY12-PHASE4-FINAL-NOOP-DECISION-20261011.md`.
- **12.9:** desktop GSC + Android GSCM console 4s polling directly user-reported normal; iOS patched binary only operator-asserted normal. Operational UI scope accepted; iOS independent binary/device proof absent. `DAY12-PHASE9-UX-OPERATOR-CLOSURE-20261011.md`.
- **12.2 (initial review, superseded below):** 11/11 non-Lobby historic installed JAR digests matched pinned release/CI bytes; at that point two Lobby aliases remained unproven. **The later 2026-10-11 resolution below establishes 13/13 exact historical provenance matches.** Runtime identity and final mandatory live gate remain separate. `DAY12-PHASE2-FINAL-PROVENANCE-REVIEW-20261011.md`.
- **12.6:** fail-closed final release chain, real-byte SHA manifest generation, signature/Android release controls and negative fixtures verified by [CI run 38066005282](https://github.com/geumyi22/Geumyi-Minecraft-System/actions/runs/38066005282) **PASS in repository scope**; actual signed Stable not published. `DAY12-PHASE6-RELEASE-CHAIN-REVIEW-20261011.md`.

The protected final release manifest remains **BLOCKED**, especially 12.5 security, 12.7 real offline boot, 12.10 private socket native binding, 12.11 real staging recovery/rollout E2E, 12.12 long soak, and the then-unresolved Lobby provenance (since resolved below). See `deploy/day12-scoped-evidence-ledger.json` for review statuses separated from exact reserved closed-scope test IDs.

## 2026-10-11 — Lobby plugin provenance resolved; final Stable still blocked

Identified original Day10 final cutover System CI run **37113499031** from `DAY10-E2E-REPORT.md`. Archived GST/GDS JAR content SHA256s match both historic installed Lobby aliases exactly; all **13/13** targeted installed plugin/agent copies are now traceable to pinned CI/release content. See `DAY12-PHASE2-LOBBY-PROVENANCE-RESOLVED-20261011.md`.

12.6 repository build/sign/manifest control CI **PASSED** in run **38066005282**, but **actual signed Stable release is a 12.13 action only**. 12.10 real native backend socket bind ownership is still `FAIL_UNVERIFIED_NATIVE_OWNER_ADDRESS`; other required offline, security, 12.11 real E2E, soak and release checks remain. No Stable signing, publish or host file replacement authorized.

## Repository-side verified evidence

- Day 12 full synthetic/read-only Safety CI: **PASS** — run `37670902211`
- source secret scan + declared-component CycloneDX SBOM + GSC identical double-build reproducibility: **PASS** — run `37670892834`
- synthetic non-production disaster-recovery drill + Recovery Kit packaging: **PASS** — run `37670892599`
- GSC 4.3.8 installer stale-payload cleanup 후 full System CI: **PASS** — run `37669908817`
- same cleanup 기준 Day 11 Host Test Package: **PASS** — run `37669908646`

These PASS results validate repository-side code/tooling only. They do not close any real server/client gate.

## Non-negotiable safety rules

1. No live mutation is called PASS from CI/static analysis alone.
2. Never force-kill Paper/Velocity for normal maintenance.
3. Every destructive or replacement flow is preflight -> backup/checkpoint -> verify -> change -> health gate -> rollback on failure.
4. Protected, golden-baseline, active-transaction, and active-rollback assets are not auto-deleted.
5. Secrets (RCON passwords, device tokens, Floodgate private keys, signing keys, GitHub tokens) never appear in reports or committed files.
6. Network/update lookup failure must not prevent an already-known-good server from starting.
7. Java and Bedrock final routing require real-client E2E evidence.
8. Day 12 may span more than one calendar day; the Day number is a milestone, not a date.

## 12.0 — Final Freeze / Golden Baseline

After Day 11 closes:
- record all component versions, commit SHA, artifact SHA-256, paths, ports, server roles and update policy;
- record Wild / Playground / Other / Lobby and three public Java/Bedrock entrypoints;
- create and protect a final known-good recovery checkpoint;
- emit:
  - `FINAL-BASELINE.json`
  - `FINAL-VERSION-MATRIX.md`
  - `FINAL-NETWORK-TOPOLOGY.json`

The Golden Baseline is immutable to automatic retention.

### 12.0 current progress — updated 2026-10-09 KST

- **12.0A — READ-ONLY capture:** server-PC operator READY recorded at **02:45 KST**. This is operator-reported live evidence; do not equate it with a new assistant-side re-run.
- **12.0B — Golden Recovery Checkpoint:** operator PASS recorded at **03:23 KST**; **4/4 FULL Golden backups** verified and protected from automatic retention.
- **12.7 cache linkage:** known-good cache Build PASS recorded at **03:45 KST**, with 84 SHA-256-listed artifacts. Actual offline-start E2E is still required.
- **12.10 unresolved blocker:** Final Verification on the real server PC at **03:47 KST** returned **18 PASS / 0 WARN / 1 FAIL** (`backend_ports_private`, no TCP listener inventory). Treat backend privacy as unverified until actual address-to-port binding evidence is collected and verifier returns mandatory FAIL=0. `Day12_TCP_Bind_Diagnostic_READ_ONLY.cmd` and synthetic Windows CI are prepared; CI PASS is not live PASS.

These are the latest records from `DAY12-REPO-PROGRESS.md`. `FINAL-RELEASE-GATES.json` deliberately remains fail-closed pending review of actual evidence and every required live gate. Do not create redundant Golden checkpoints or rebuild the cache merely because an older runbook section still lists their setup steps.

## 12.1 — ResourcePack / DataPack managed deployment

ResourcePack:
- Java and Geyser/Bedrock pack inventory;
- SHA-1/SHA-256 calculation;
- server.properties/resource-pack property update;
- staging and verification;
- per-server targeting;
- rollback to previous verified pack.

DataPack:
- ZIP/pack metadata and `pack_format` validation;
- server targeting;
- staging + backup;
- next-start/restart activation;
- rollback and audit.

No automatic deployment of an artifact that has not passed validation.

## 12.2 — Full component update inventory

Fleet view covers:
- GSC
- GSCM
- GST
- GDS
- StatusAgent
- Technology
- Chemistry
- ResourcePack / DataPack
- Geyser / Floodgate
- ViaVersion / ViaBackwards

For each component expose, where applicable:
- installed version;
- latest verified version;
- channel/pin/hold/manual policy;
- last-known-good;
- rollback asset;
- validation/update history.

Paper remains compatibility-check + notify + explicit operator approval by default.

## 12.3 — Whole-system Health Check

Add a read-only whole-system health report for:
- GSC Host;
- Windows service/startup state;
- server directories;
- Java listeners/status;
- RCON;
- Velocity public entrypoints;
- Geyser/RakNet;
- GDS/StatusAgent/GST;
- plugin/DataPack/ResourcePack inventory;
- backup freshness/integrity;
- update transaction residue;
- rollback readiness;
- disk capacity;
- duplicate/conflicting ports.

Export JSON suitable for support/debugging without secrets.

## 12.4 — Storage, backup and log lifecycle

**2026-10-10 fast-first decision:** prior live lifecycle dry-run identified **zero** eligible backup/log candidates. The proposed policy protects Golden/checkpoint/active-transaction backups, permits Trash-only movement and forbids automatic permanent delete. Therefore no Lifecycle Apply or repeated backup inventory is justified for closure. **Review recommendation: NO ACTION; deployment/policy approval not claimed**. See `DAY12-QUICK-FIRST-20261010.md`.



Backup policy:
- configurable recent/daily/weekly retention;
- protected/pinned backup exemption;
- Golden Baseline exemption;
- active transaction/rollback reference exemption;
- disk-space preflight before backup/update;
- dry-run before retention deletion.

Logs:
- bounded rotation;
- crash-log preservation;
- configurable retention/max size;
- no silent deletion of current incident evidence.

## 12.5 — Security hardening

CI/runtime checks:
- secret scan;
- dependency/security scan;
- SBOM;
- provenance;
- artifact SHA/signature verification;
- Windows service/folder ACL review;
- firewall/public-port review;
- localhost/mobile API exposure review.

Security findings are recorded separately from runtime health.

## 12.6 — Trusted / reproducible release chain

Target chain:

```
source commit
 -> deterministic build inputs
 -> tests
 -> security/SBOM
 -> artifact hashes
 -> provenance/signature
 -> deployment manifest
 -> GSC verification
 -> staged deployment
 -> health gate
```

Stable promotion requires all mandatory gates.

## 12.7 — Offline operation / shared artifact cache

Maintain verified local cache:
- current;
- previous;
- known-good.

Test with update/network lookup unavailable:
- GSC still starts;
- Velocity and all backends still start from known-good local state;
- failed update discovery is reported but does not break service.

## 12.8 — Disaster Recovery drill

Synthetic/non-production destructive cases:
- damaged GSC binary;
- damaged plugin artifact;
- interrupted transaction;
- invalid config;
- failed startup;
- failed update health check.

Verify detect -> block unsafe commit -> rollback -> health -> recovery.

Build a `Geumyi-Recovery-Kit` containing recovery scripts/manifests/documentation but **no plaintext secrets**.

## 12.9 — Final UX cleanup

**Console live log UX source fix prepared 2026-10-10:** GSC desktop previously refreshed only on manual/navigation; GSCM had 4-second polling disabled by default. Both updated at source to 4-second active-console polling with manual override; requires host/client binary rollout and actual UI observation before runtime PASS. This is not WebSocket streaming. No RCON/WebSocket protocol or backend changes.


Remove or retire:
- temporary test-only controls;
- duplicate/obsolete wording;
- FIX/FIX2/HOTFIX test packaging residue where no longer required;
- stale version labels.

Unify Korean status/error wording and make GSC/GSCM present production-state information consistently.

## 12.10 — Read-only Final Verification tool

Create `Geumyi_Final_Verification.cmd` that performs no mutation and checks at least:
- files/versions/hashes;
- Windows service/startup;
- Java/Bedrock/Velocity/RCON;
- GDS/GST/StatusAgent;
- plugins/ResourcePack/DataPack;
- backup/rollback/update state;
- disk;
- security configuration.

It emits a machine-readable report plus PASS/WARN/FAIL counts.

## 12.11 — Final live E2E

**Bedrock resource-pack Lobby→backend fix (2026-10-10): RESOLVED, USER-REPORTED NORMAL.** Original 3 packs + 212-definition custom mapping are installed across three Geyser-Velocity instances (9 archives + 3 mappings); all three proxy process-pair restarts were host-verified via Java/RakNet probes; the operator then replied `정상` to the Bedrock pack rejoin and server-switch test instructions. The user outcome is a smoke-level acceptance, not independently itemized proof of each port, language key, sound or icon. **The 25-case Day12.11 final E2E remains open** pending all required evidence; no Stable/Day12 completion claim.

Server PC:
- Windows reboot;
- GSC/Velocity/backend startup;
- no orphan/duplicate processes.

Java real client:
- public entry -> Lobby;
- Lobby <-> Wild/Playground/Other;
- last-location restore.

Bedrock real client:
- same routing/return behavior through Geyser/Floodgate.

Operations:
- start/stop/restart;
- intentional stop -> OFFLINE;
- unexpected loss -> RECOVERING;
- console/RCON;
- schedule;
- backup/verify/restore;
- update dry-run/apply/rollback.

GSCM:
- Android and iOS flows as applicable;
- status/control/console/backup/update;
- device revoke/restore/delete/re-pair.

## 12.12 — Soak test

**2026-10-10 engineering readiness:** `tools/day12/Day12_Phase12_Continuous_Soak_READ_ONLY.ps1` adds an optional **continuous, read-only, eight-hour** alternative to the existing start/end snapshot method. It samples Java/GSC process identity and GSC Java TCP/Bedrock RakNet application-layer responses every five minutes. [Windows PowerShell 5.1 synthetic/packaging CI PASS](https://github.com/geumyi22/Geumyi-Minecraft-System/actions/runs/38055832685); artifact `Geumyi-Day12-8H-Soak-READ-ONLY`, private server-PC sample details not shared. The tool **has not run for eight hours on the user's server**. Only share the sanitized final summary JSON after a complete session; `result=REVIEW_REQUIRED` always until independently reviewed. It cannot prove real client gameplay, native socket binding or Stable readiness.



Before closure:
- active-use window;
- extended idle window (target 8–12 h where practical).

Watch for:
- memory/handle growth;
- CPU spike;
- duplicate processes;
- restart loops;
- WebSocket churn;
- RCON false warning recurrence;
- disk/log growth;
- backup/update failures.

## 12.13 — Final release and Maintenance Mode handoff

Required closure artifacts:
- `FINAL-E2E-REPORT.md`
- `FINAL-BASELINE.json`
- `FINAL-VERSION-MATRIX.md`
- `FINAL-SECURITY-REPORT.json`
- `FINAL-DR-REPORT.json`
- `FINAL-HEALTH-REPORT.json`
- `Geumyi-Recovery-Kit.zip`
- `Geumyi_Final_Verification.cmd`

Only after all mandatory gates pass:
- create final Stable release/tag;
- mark Day 1–12 complete;
- switch the project to **Maintenance Mode**.

## Final gates

Day 12 is complete only when:
- all required CI/build/security gates pass;
- server-PC final verifier has FAIL=0 for mandatory checks;
- Java and Bedrock real-client E2E pass;
- backup/restore/update/rollback live paths pass;
- DR drill passes;
- offline known-good startup passes;
- GSCM real-device flows are checked;
- soak test has no unresolved critical defect;
- no unverified item is labeled PASS.


## Execution responsibility split

### ChatGPT / repository-side work
- prepare source changes, scripts, manifests, validation tools and rollback logic;
- update GitHub documentation/version matrices as each Phase is verified;
- review logs/reports supplied by the operator and determine PASS/WARN/FAIL without inventing runtime results;
- keep changes reversible and preserve historical recovery evidence;
- prepare final release/verification artifacts only after their required gates pass.

### Operator / user-side work
- run scripts that require the real Windows server or management PC;
- perform real Java/Bedrock/GSCM device tests when a Phase requires them;
- provide generated JSON/log reports or exact error output when a live gate fails;
- approve intentional live mutations such as restart/update/restore tests when the Phase reaches that gate;
- perform the final reboot, live-client E2E and soak window.

The repository-side work may proceed ahead of live gates, but no live item is marked PASS until the corresponding real-machine evidence is supplied.
