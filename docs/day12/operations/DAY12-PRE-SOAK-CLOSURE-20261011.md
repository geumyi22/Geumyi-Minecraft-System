# Day 12.0–12.11 pre-soak closure — 2026-10-11 KST

**Decision:** Complete all defensible repository-side preparation before 12.12. **Not** a Day12.0–12.11 all-real-runtime PASS. **Stable / Maintenance remain blocked.** No live server/service/backup/world/plugin/firewall/ACL/update was touched by this review.

## Accepted, do not rerun unchanged evidence

| Phase | Proven scope | Separate unproved requirement |
|---|---|---|
| 12.0 | Real protected Golden full backups **4/4**, baseline operator report | Newly signed final manifest |
| 12.1 | Wild/Playground Java packs, 3 Bedrock packs and routing operator-accepted; 212 mapping static refs matched; 3 proxy pair/UDP checks previously passed | GSC managed-content auto-adoption/deploy is **disabled**, not required to operate existing packs; active deployed-byte and managed-rollout validation not done. 2026-10-11 phase1 apply script now rejects missing expected SHA256/Java SHA1, duplicate IDs/targets, invalid paths and URLs before transaction; Windows Safety CI must pass before claiming source closure |
| 12.2 | 13/13 historical JAR digests match pinned CI/release bytes; exact Lobby aliases match Day10 CI **37113499031** | Fresh loaded plugin runtime identity and final live release attestation |
| 12.3 | Real whole-health **15 PASS, 0 WARN/FAIL** in original capture | Does not attest kernel TCP bind address |
| 12.4 | Real dry-run zero eligible candidates; operator-approved **NO ACTION**; Golden/logs protected | Scheduled retention policy not installed, deliberately unnecessary for zero candidates |
| 12.5 | Source security/SBOM CI; prior LAN/Tailscale API unauthenticated 8/8 HTTP401; actual Windows ActiveStore and ACL read-only captures | **OPEN:** broad Allow-rule ownership/effective filtering, GSC ProgramData inherited BUILTIN_USERS file-create rights; no safe justification to disable any broad rule or ACL automatically |
| 12.6 | Repository release chain fail-closed CI + checked SHA, signature order, Android persistent-signer policy, Git tag re-use veto | **OPEN:** final signed Stable publish and actual install; iOS workflow builds **unsigned IPA** |
| 12.7 | Real cached files **84/84 SHA256+size PASS**; disposable Windows CI real GSC 4.3.8 and Paper 26.3 boot while GSC upstream-update HTTPS proxy intentionally unavailable | **OPEN:** real user's offline known-good startup; earlier Playground precheck blocked by automatic-update policy. No NIC/router/firewall disruption permitted on the operator machine |
| 12.8 | Disposable disaster-recovery and rollback CI PASS | Live destructive restore intentionally not executed |
| 12.9 | Real GSC desktop + GSCM Android console auto-refresh operator-accepted; old Android/iOS status/reconnect user-accepted | New patched iOS IPA 4-second console feature operator-asserted, not separately device proven |
| 12.10 | Configured exact 127.0.0.1 backend properties, 4/4 GSC guard precheck; tested LAN IPv4/IPv6 and Tailscale IPv4/IPv6 paths all **0/8 private TCP** with positive public controls; server API unauthorized 8/8 401 | **FAIL_UNVERIFIED_NATIVE_OWNER_ADDRESS**: Windows native active IPv4/IPv6 listener/owner proofs incomplete. TCP and historical WFP tools gave inconsistent/missing observations. Repeating failed scans/restarts is not the solution |
| 12.11 | User accepts normal Java/Bedrock/game/remote console; 18-item remainder list: **15 user-waived**, **#2 independent real host scoped process-role match**, 16 disposed in their exact scopes | **#12** actual disposable-process unexpected loss -> RECOVERING, **#17** real staging signed update Canary/Rollback not executed. CI state machine / temporary-file rollback are not real staging process E2E. Full 25-case canonical form remains open |

## Minimal remaining engineering / operator boundaries (before 12.12)

1. **12.1:** Preserve existing working packs; do not force manual/managed migration, duplicate install, write server.properties or replace Dropbox packs. The manifest is intentionally disabled. New installer validator is a source-only improvement, not an approved managed deployment.
2. **12.5:** Resolve only *identified* current effective Windows firewall/ACL risks. Existing firewall inventory is extensive but rule ownership is incomplete; no safe unattended removal. A least-privilege ACL/firewall proposal must identify the affected host rule/ACE privately, stage it, protect management access, and include rollback and separate operator authorization.
3. **12.7:** No operator outage needed for CI proof; genuine operator-cache offline startup remains independently required by the strict final gate. The planned Windows Sandbox route failed prerequisite checks; enabling hypervisors or disabling networking on the family server is not authorized.
4. **12.10:** Retain current native-owner strict FAIL. Only an independent actual OS owner/address proof or an explicitly authorized, *separately specified* compensating-controls policy with effective firewall evidence could resolve it. Existing negative probes are positive *scoped reachability* evidence, not exclusive bind proof.
5. **12.11:** Preserve 16/18 accepted scopes without repeated routine user prompts. Real #12 fault injection and #17 signed canary apply/rollback require isolated staging and a verified teardown/restore path; never kill live Paper or make unsupervised production deployments.
6. **12.6/12.13:** Do not modify `FINAL-RELEASE-GATES.json` or publish Stable solely because a CI or operator-accepted waiver is green. Missing production safety and soak gates remain.
7. **12.12:** Only begin a real 8–12h soak once the operator chooses a safe uninterrupted operating window. Never claim it ran from its successful Windows synthetic packaging CI.

## No-repeat and privacy rules

Existing Golden 4/4, cache 84/84, real Bedrock 3 proxy routing, prior accepted Java/GSCM functional tests, external 0/8 scoped checks and unauthenticated 401s do not need repetition absent configuration drift. Never publish private paths, addresses, tokens, user-uploaded pack bytes or raw host report hashes. This document is a transparent pre-soak handoff, not an override of final release evidence.
