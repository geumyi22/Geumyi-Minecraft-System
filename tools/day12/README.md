# Day 12 tools

Day 12 is the final production-hardening milestone. Tools are intentionally split into **READ-ONLY**, **dry-run**, **synthetic**, and **explicit-confirmation mutation** classes.

## Easiest later starting point

`Day12_Collect_All_READ_ONLY.cmd` collects every safe read-only report that can be gathered in one session. It does **not** create Golden backups, apply packs, restart anything, change policy, or build the known-good cache.

## Phase tools

- **12.0A** `Day12_Phase0_Golden_Baseline_READ_ONLY.cmd` — live baseline capture.
- **12.0B** `Day12_Phase0B_Golden_Checkpoint.cmd` — explicit-confirmation protected full Golden backups; all targets must already be offline.
- **12.1** `Day12_Phase1_Content_Preflight_READ_ONLY.cmd` — ResourcePack/DataPack/Geyser pack inventory. Live Java apply engine is `Day12_Phase1_Managed_Content_Apply.ps1` and is confirmation/offline/hash gated.
- **12.2** `Day12_Phase2_Component_Inventory_READ_ONLY.cmd` — component/update inventory.
- **12.3** `Day12_Phase3_Health_READ_ONLY.cmd` — whole-system health.
- **12.4** `Day12_Phase4_Storage_Log_DRY_RUN.cmd` — retention/log cleanup candidates only.
- **12.5** `Day12_Phase5_Security_Audit_READ_ONLY.cmd` — runtime listener/ACL/firewall exposure summary.
- **12.7** `Day12_Phase7_KnownGood_Cache.ps1` — Audit or explicit-confirmation Build; Build requires a Phase 12.0B PASS report.
- **12.8** `Day12_Phase8_DR_SYNTHETIC.ps1` — temp-only disaster-recovery drill used by CI.
- **12.10** `Geumyi_Final_Verification.cmd` — canonical final read-only verifier.
- **12.12** `Day12_Phase12_Soak_READ_ONLY.cmd` — soak start/end snapshots.

## Recovery Kit

`recovery-kit/` contains hash-gated recovery helpers. The CI packs them as `Geumyi-Recovery-Kit.zip`. No plaintext credentials belong in the kit.

## Final release

`FINAL-RELEASE-GATES.json` is fail-closed. The final closure workflow only packages evidence after every repository and live gate has been explicitly changed to PASS. It does **not** silently promote a release.

Historical Day 8–11 recovery evidence is intentionally retained.
