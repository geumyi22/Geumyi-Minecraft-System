# GSC Release Channel Policy — 2026-10-17

Status: **policy and UI safety hardening proposed on a review branch; not production deployment**.
Applies to GSC Host/Client Update Center, per-server managed plugin deployment, GSCM remote policy viewing, and release promotion. Do not treat this document as evidence that a new build is installed or that production gates have passed.

## Meaning of the channels

| Channel | Purpose | Typical audience / target | Required release evidence | Allowed deployment behavior |
| --- | --- | --- | --- | --- |
| **Stable** | Known-good routine operation | Real Wild / Playground / Other / Lobby; regular GSC/GSCM users | Tests, verified build provenance, trusted manifest signature plus hashes **when using automated deployment**, compatible dependencies, live health/rollback evidence, unresolved security gates cleared, operator release approval | Normal default for **new** configurations. Automated install only when existing explicit enable/managed policy and the **strictly verified signed** deployment is available. |
| **Beta** | Feature-complete release-candidate and compatibility validation | Opt-in devices/test targets | Component CI and documented reproducible artifacts, trusted signature/hashes for automated manifests, explicit open risks and rollback plan | Opt-in. Never silently become production Stable, never automatically change another server's policy. |
| **Canary** | Early experiment / rapid defect detection | Isolated disposable test or one explicitly approved test target at a time | At least targeted checks and provenance; trusted signature/hashes **before any updater can consume it**; known limitations stated | Explicit opt-in. Prefer read-only or offline tests first; no fleet-wide automatic enable, restart or release promotion. |

**Channel is not a confidence assertion.** A GitHub release label `stable` or a successful package build is not the same as passing `FINAL-RELEASE-GATES.json` or releasing an Ed25519-signed `deployment-stable.json`.

The published 2026-10-11 GSC 4.5.1 / GSCM 1.5.1+151 release is a **manually installable Stable-labelled package**, not proof of complete strict production Stable gating. Its live-device installation/E2E must be recorded separately.

## Configuration and precedence

- **Fresh installs / missing or invalid channel values:** default to `stable`. Update **Enabled** remains **false** on first install; selecting Stable does not enable installation.
- **Existing persisted values:** `stable`, `beta`, `canary` remain unchanged when valid. In particular, legacy `beta` global settings and opted-in canaries must **not** be silently migrated.
- Global `UpdateConfig.Channel` is the inherited default. Per-server `UpdateChannel` is `inherit | stable | beta | canary`; an explicit server value wins over global.
- `managed | manual | hold` are **installation policies**, not release channels. `managed` may perform next-start updates when explicitly enabled; `manual` requires operator action; `hold` does not install new releases.
- A release **pin** narrows selection to an exact release; a pin never bypasses trusted-signature, hash, target, dependency, security, or health checks.
- Channel changes and Canary rollout policy changes alone must not restart any Minecraft server, Velocity proxy, GSC Host, or GSC Client.
- If a new configuration is unknown or invalid, fail to the safe Stable selection, but never mutate the persisted known non-Stable choice in an existing file as a side effect of ordinary status reads.

## Promotion and quarantine gates

1. Build and test candidate from identifiable commit; record CI run, artifact hashes and signing provenance.
2. For updater-consumable manifests, verify Ed25519 signature against a **pretrusted** key and verify content SHA-256/size, target and compatibility; do not trust a verification key from the downloaded release.
3. Canary: test isolated target, capture startup and functionality, retain last-known-good and recovery path. A `Draft`/CI-only release is **not** eligible for automatic discovery or installation.
4. Beta: verify end-to-end behavior on approved non-production targets and regression tests; no automatic promotion based merely on elapsed time or CI status.
5. Stable: require every mandatory release/security gate and independent live verification, including backend port privacy, effective ACLs, production backup/restore readiness, actual Windows/Android/iOS platform constraints, operator approval, and correct signed promotion artifact. Any FAIL/BLOCKED/UNKNOWN => **no strict Stable promotion**.
6. Reject failed or revoked releases, store an audit event, preserve known-good artifacts and do not retry a rejected release indefinitely. A network/manifest/hash/compatibility failure must not prevent starting the last-known-good Minecraft server.
7. No automatic changes to the real server, worlds, backups, firewall, ACLs, or external Paper/Geyser/Velocity configuration during release-policy review.

## Operator UX

- Show the selected channel together with its **purpose** and risk level. Explain that `inherit` uses the current global value.
- When changing global or per-server effective channel **to Beta/Canary**, show an explicit risk confirmation before saving. A confirm is an *advisory UI layer*, never a substitute for backend signing, authorization and final release gates.
- Do not switch an existing account or server to Stable during the UI change; only new/missing/invalid defaults change.
- Keep GSC self-update separate from server/plugin policy and GSCM distribution. A Windows updater manifest signature does not imply Windows Authenticode signing, and an unsigned iOS IPA is not directly installable.
- Preserve Canary rollout order and guardrails: `Playground -> Wild -> Other -> Lobby`, only if the operator explicitly starts/promotes each stage and predecessor health passes. An OFFLINE target remains OFFLINE until separately authorized.
- Dry-run/check-only operations must remain non-mutating.

## Validation checklist

- [ ] Fresh Host/Setup default returns `stable`, with `Enabled=false`.
- [ ] Unknown/missing channel normalizes to `stable`; explicit `beta`/`canary` survives normalization and save/load.
- [ ] Inheritance and per-server override unchanged, and managed/manual/hold semantics unchanged.
- [ ] UI explains each channel and requires confirmation on risk-increasing channel changes; cancel must not send any policy write.
- [ ] Go unit tests PASS, Windows build/test PASS, UI smoke on GSC Client PASS.
- [ ] GSCM Android/iOS device UX examined separately; no unsupported iOS installation claims.
- [ ] No host service restart, real server changes, release publication, branch merge or Stable promotion before independent review.

## Related historical and security references

- `docs/reference/DEPLOYMENT-ARCHITECTURE.md` — historical implementation/architecture. Some sections are older plans, not today's E2E status.
- `docs/history/day-11/DAY11-PLAN.md` — historical Update Center 2.0 validation.
- `MAINTENANCE-MODE.md`, `FINAL-RELEASE-GATES.json` — **strict production Stable guard**; do not bypass.
- GitHub draft PR #53 is security/ACL integration work and is **not** merged or deployed by this channel policy work.
