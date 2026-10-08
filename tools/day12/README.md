# Day 12 tools

Day 12 is the final production-hardening milestone. Tools are intentionally split into **READ-ONLY**, **dry-run**, **synthetic**, and **explicit-confirmation mutation** classes.

## Easiest later starting point

`Day12_Collect_All_READ_ONLY.cmd` collects every safe read-only report that can be gathered in one session. It does **not** create Golden backups, apply packs, restart anything, change policy, or build the known-good cache.

## Phase tools

- **12.0A** `Day12_Phase0_Golden_Baseline_READ_ONLY.cmd` — live baseline capture.
- **12.0B** `Day12_Phase0B_Golden_Checkpoint.cmd` — explicit-confirmation protected full Golden backups; all targets must already be offline.
- **12.1** `Day12_Phase1_Content_Preflight_READ_ONLY.cmd` — ResourcePack/DataPack/Geyser pack inventory. Live Java apply engine `Day12_Phase1_Managed_Content_Apply.ps1` is confirmation/offline/hash gated and auto-rolls back failed transactions; `Day12_Phase1_Managed_Content_Rollback.ps1` provides explicit manual rollback.
- **12.2** `Day12_Phase2_Component_Inventory_READ_ONLY.cmd` — component/update inventory.
- **12.3** `Day12_Phase3_Health_READ_ONLY.cmd` — whole-system health.
- **12.4** `Day12_Phase4_Storage_Log_DRY_RUN.cmd` — retention/log cleanup candidates only. After review, `Day12_Phase4_Lifecycle_Apply.cmd` moves eligible backups/logs to recoverable Trash areas (no permanent delete), and `Day12_Phase4_LogTrash_Recovery_Preflight.ps1` validates recovery material.
- **12.5** `Day12_Phase5_Security_Audit_READ_ONLY.cmd` — runtime listener/ACL/firewall exposure summary.
- **12.7** `Day12_Phase7_KnownGood_Cache.ps1` — Audit or explicit-confirmation Build; Build requires a Phase 12.0B PASS report.
- **12.8** `Day12_Phase8_DR_SYNTHETIC.ps1` — temp-only disaster-recovery drill used by CI.
- **12.10** `Geumyi_Final_Verification.cmd` — canonical final read-only verifier.
  - `Day12_Phase10_Bind_Evidence_READ_ONLY.cmd` — separate real-host, read-only evidence tool. Reads only the `server-ip`, `server-port`, `enable-rcon` and `rcon.port` fields from each backend `server.properties`; fingerprints the file and compares two Windows TCP listener snapshots. Non-loopback addresses and all credentials are redacted. It also samples GSC online state before/after listener discovery and probes localhost Java ports (TCP connect only); these probes cannot prove private binding. Its output is **CAPTURED_REVIEW_REQUIRED**, never a substitute for `Geumyi_Final_Verification.cmd` PASS. Missing listeners or blank `server-ip` must not be treated as private bind evidence.
  - `Day12_TCP_Bind_Diagnostic_READ_ONLY.cmd` — native Windows TCP listener/bind evidence collection for a fail-closed `backend_ports_private` investigation; synthetic Windows CI PASS does not prove live listener privacy.
- **12.12** `Day12_Phase12_Soak_READ_ONLY.cmd` — soak start/end snapshots.

## Recovery Kit

`recovery-kit/` contains hash-gated recovery helpers. The CI packs them as `Geumyi-Recovery-Kit.zip`. No plaintext credentials belong in the kit.

## Final release

`FINAL-RELEASE-GATES.json` is fail-closed. The final closure workflow only packages evidence after every repository and live gate has been explicitly changed to PASS. Final Stable publication is separately handled by `.github/workflows/day12-final-release.yml`, which re-runs safety/security/system/mobile build gates before publishing a signed immutable Stable release.

Historical Day 8–11 recovery evidence is intentionally retained.
