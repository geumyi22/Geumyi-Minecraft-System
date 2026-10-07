# Day 12 — Final Production Hardening & Closure

Status: **READY TO START — Day 11 closed on GSC 4.3.8 / GSCM 1.1.5+117**
Role: **final project milestone before Maintenance Mode**

Day 12 is not a feature-dump. Its purpose is to leave Geumyi Minecraft System in a state where normal operation no longer depends on manual file copying or frequent development work.

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
