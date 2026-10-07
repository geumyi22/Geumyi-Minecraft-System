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
