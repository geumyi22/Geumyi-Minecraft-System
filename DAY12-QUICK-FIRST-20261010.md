# Day 12 — QUICK-FIRST operator plan (2026-10-10 KST)

**Decision:** do all short and safe work before the 8–12 hour soak. This is a prioritized sequence, **not** a claim that the live E2E items below were already executed.

## Already verified, do not repeat

- Phase 12.0 Golden: **4/4 full protected** backups (operator 2026-10-09).
- Phase 12.3 real GSC/servers health: **15 PASS / 0 WARN / 0 FAIL** in earlier scoped capture. Subsequent Day12.11 parent/child scoped Velocity restart **3/3 PASS** with GSC Java TCP / Bedrock RakNet probes healthy (operator JSON 2026-10-10 22:12).
- Phase 12.4 earlier on-host backup/log dry-run **zero candidates**. No cleanup/trash move is justified solely for Day12 completion.
- Phase 12.8 synthetic disaster-recovery and CI **PASS** (not a destructive real-world restore).
- Bedrock Lobby → backend custom resource packs: **RESOLVED** by operator-reported real-game `정상`; 9 original archives + 3 matching JSONs were staged and approved; do not reinstall/restart unless regressions appear.
- Known-good 84-artifact cache verified, but NOT equivalent to offline-start E2E.
- Day12.10: current LAN/overlay/IPv6 tested paths showed no private TCP reachability, GSC unauthorized requests returned HTTP 401; **exclusive OS native bind/owner security gate still FAIL**. Do not confuse these.

## Quick now, no service disruption

| Priority | Scope | Operator time target | Concrete test | Evidence boundary |
|---|---|---|---|---|
| 1 | 12.4 lifecycle | Repo-side completed | Approve a **no-action decision**: keep policy `PROPOSED_DEFAULTS_REVIEW_AFTER_LIVE_DRY_RUN`, do not invoke lifecycle Apply when last real dry-run has zero candidates, retain all Golden 4/4 and incident logs | **Review-only; not** production retention-policy deployment |
| 2 | 12.11 GSCM | ~3–5m | On Android **and** iOS, open GSCM, verify pairing/session, current server states, reconnect/refresh, no authentication leakage or unexpected failures. **Do not stop/restart servers.** | Two independent device observations required; existing Day 11 success not automatically fresh Day 12 PASS |
| 3 | 12.11 GSC RCON & WS | ~2–3m | In current GSC console select intended server, run read-only `list` command (do not issue destructive/admin changes). Observe RCON reply and status update / WebSocket reconnect after a harmless refresh | `GSC_CONSOLE_RCON_CONTROL` and `GSC_WS_RCON_RECONNECT` must be operator-observed separately |
| 4 | 12.11 Java | ~5–10m | Using actual Java client, check public 25565/25566/25567 each reaches Lobby; move Lobby→Wild→Playground→Other→Lobby and confirm per-backend last location; verify existing Java packs on Wild/Playground without redeploying | Do not call these PASS merely from TCP probes or earlier Day 10 report |
| 5 | 12.11 Bedrock supplemental | Only if needed | The user's `정상` already closes the reported pack-switch issue. Detailed BACAP Korean, representative Chemistry/Technology item models, individual Playground sound, three separate Geyser login entrypoints may be selectively checked for individual 25-case form status | Do **not** assume a single `정상` asserts every specific test |
| 6 | 12.2/12.5 component/security review | Repo-side or separate focused proof | Reuse existing inventory and firewall/ACL evidence, do not rerun large host scans. Exact release hash provenance and effective ACL/allow candidates are still independent | Status remains REVIEW_REQUIRED where no trusted signed source/OS effective proof |
| 7 | 12.7 offline known-good | Later, risk gated | Existing Playground real precheck blocked only because auto-update policy not demonstrably hold/manual. Prefer disposable/staging offline update-source failure test, never disconnect household/router or alter production updater just for green | Full production offline start still OPEN |
| 8 | 12.10 kernel bind/owner | Later, risk gated | Reconcile a genuinely independent process/socket attribution source or a separately approved compensating-control policy | Canonical `backend_ports_private=FAIL`; never override based on old partial listener tables |
| Last | 12.12 soak | >=8h | Run new optional CI-tested read-only continuous monitor in an uninterrupted window; inspect process stability, client/GSCM gameplay and logs | Summary REVIEW_REQUIRED until human review; Stable blocked |

**No broad authorization:** reboot, firewall/ACL changes, live world restore, forced process kill, network outage and Stable promotion remain outside this short-work sequence and require their own approved/verified procedure.

## Day 12.11 canonical evidence discipline

The authoritative `deploy/day12-final-live-e2e-checklist.json` contains exactly **25** cases. Non-disruptive operator checks can be conducted before the nine disruptive entries. The existing `tools/day12/validate_phase11_operator_e2e.py` explicitly rejects unsupported PASS entries, unapproved disruptive PASS or missing time/evidence fields. We will not auto-fill PASS based on GSC network probes, prior Day11 success or the broad `정상` reply.

**Next operator action:** perform #2 GSCM Android+iOS session/status check and #3 read-only GSC console `list`, then report whether each was normal. These tests need the user's real devices and cannot be completed using GitHub CI.

## Phase 12.4 reviewed no-action rationale

The policy `deploy/day12-lifecycle-policy.json` is **proposed**, not deployed (`status=PROPOSED_DEFAULTS_REVIEW_AFTER_LIVE_DRY_RUN`). Safety settings are consistent with risk avoidance:
- `backup.protected_exempt=true`, `checkpoint_exempt=true`, `active_transaction_exempt=true`, `apply_mode=trash_only`.
- `trash.permanent_delete_automatic=false`.
- Distinct normal/crash log retention and disk warning/stop thresholds exist.

**Review disposition: NO CLEANUP ACTION RECOMMENDED** because the earlier real dry-run found zero backup/log candidates; keep the policy proposed, do not move files, do not delete old backups, do not regenerate Golden and do not claim 12.4 production retention implementation PASS. If future nonzero candidates emerge, an explicit new preview and targeted approval are required.
