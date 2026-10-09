# Maintenance Mode Handoff

Status: **BLOCKED until FINAL-RELEASE-GATES.json is fully PASS**

When Day 12 closes:

- feature work stops by default;
- Stable is the normal channel;
- Beta/Canary are used only for deliberate maintenance testing;
- security/compatibility fixes, Minecraft/Paper/Geyser compatibility and critical operational defects remain supported;
- every runtime replacement still uses backup/checkpoint -> verify -> apply -> health gate -> rollback;
- Golden Baseline and known-good cache remain protected;
- no automatic permanent deletion of protected/Golden assets;
- routine diagnostics start with `Geumyi_Final_Verification.cmd`.

## Release handoff checklist

1. All repository gates = PASS.
2. All live gates = PASS.
3. `FINAL-E2E-REPORT.md` = PASS.
4. `FINAL-HEALTH-REPORT.json` mandatory FAIL=0.
5. `FINAL-SECURITY-REPORT.json` has no unresolved critical finding.
6. `FINAL-DR-REPORT.json` synthetic drill PASS.
7. Soak report reviewed with no critical leak/restart-loop issue.
8. Final signed Stable release produced through the existing verified secure-release chain.
9. Only then set `stable_release_allowed=true` and `maintenance_mode_allowed=true`.


## Fail-closed final Stable promotion guard — 2026-10-10

- `FINAL-RELEASE-GATES.json` must explicitly retain **all** expected repository and live keys, including `live_gates.phase_12_10_backend_ports_private`. Deleting an unresolved mandatory key is not equivalent to PASS. Unknown additional gates remain blocking unless individually PASS.
- Final review token `status=VERIFIED_ALL_MANDATORY_GATES` and both `release.*_allowed=true` are valid **only after** every mandatory check has genuine evidence. The default `BLOCKED_UNTIL_ALL_MANDATORY_GATES_PASS` must remain while any item is unresolved.
- Both Final Closure and Final Stable workflows also call `tools/day12/validate_final_closure_evidence.py`. The actual `FINAL-HEALTH-REPORT.json` must be a non-synthetic, non-fixture read-only capture with 0 mandatory failures, explicit `backend_ports_private=PASS`, native IPv4 **and** IPv6 OWNER_PID sources CAPTURED and positive native owner-source inventory. No netstat-only, startup-log-only or CI fixture will unlock Stable.
- `FINAL-SECURITY-REPORT.json` must independently record `runtime_acl_firewall_api_review=PASS`, `final_result=PASS` and an empty verified critical finding list. A stale partial security report or 12.10 native bind failure vetoes promotion, even if self-declared release flags say true.
- CI synthetic tests verify the **validator's rejection logic only**, not that any real Windows private port is correctly attributed or protected. Repository JSON is self-reported and does not cryptographically authenticate a live host; retain privately reviewed source artifacts and operator approval. All production operational changes still require preflight, protected Golden restore readiness and separate operator decision.
- During the current Day 12 incident `backend_ports_private` is **FAIL**; this maintenance handoff and Stable publication therefore remain BLOCKED.
