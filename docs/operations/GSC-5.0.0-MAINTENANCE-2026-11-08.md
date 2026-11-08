# GSC 5.0.0 local maintenance candidate — 2026-11-08

Scope: explicitly authorized preservation-first maintenance and play-readiness checks. Based on public tag `gsc-v5.0.0` / `cd25f677e3f6380892255fbd925666c8a1b9be77`. This branch is not the published Stable and does not change its tag, release assets, deployment manifest, main branch or formal release gates.

## Changes

- Separate the bounded two-minute external JAR transfer budget from the unchanged 20-second metadata timeout. Preserve HTTPS, trusted initial hosts, file-size cap and SHA-256 verification; reject HTTP redirect downgrade.
- Preserve cancelled/failed download cleanup. Refuse concurrent external staging and unknown component IDs. Use collision-resistant staging directory names and exclusive temporary files.
- Persist failed staging plans and per-component reasons, even when zero artifacts succeed. Empty plans cannot be applied; do not silently fall back to an older successful plan.
- Route external status/staging through the existing long-operation Client transport, retaining the short timeout for normal health/status requests.
- Prevent duplicate staging clicks, clear stale apply roots and retain existing UI layout and explicit apply confirmation.
- Optional `build_revision` identifies locally compiled Host/Client maintenance binaries. Public version compatibility remains 5.0.0; SHA-256 and build revision must distinguish these binaries from the signed public release. The existing installed Setup and public release remain unchanged.

## Tests performed before deployment

- Baseline Windows `go test ./...`: PASS.
- Modified Windows `go test ./...` and `go vet ./...`: PASS before final build-identity addition; rerun required after final changes.
- Regression coverage includes a delayed real TLS response body, successful SHA-256, short-budget timeout cleanup, cancelled downloads, corrupt payload rejection, untrusted initial host and HTTP downgrade rejection, failed-plan persistence, empty-plan apply rejection, duplicate/unknown stage requests, and a delayed reverse-proxy staging response.

## Operational safety

An offline byte-for-byte copy of the four server trees plus installed binaries, selected private configuration and proxy files was created locally before mutation. 11,351 copied files (19.07 GiB) passed SHA-256 readback. Private backup paths/configuration/tokens are not committed here. Original worlds and player data are not reset, pruned or replaced. AutoSaveWorld remains installed; its unsupported forced region-cache flush option is disabled separately, retaining save and backup settings. Existing Windows Scheduler ownership of Velocity remains unchanged.

## Evidence boundaries

Unit/integration tests do not prove authenticated Minecraft gameplay, remote/mobile E2E, long-duration soak, or production update rollback. Live deployment, staging, proxy/Paper startup, UI observations and protocol checks must be reported separately with observed results. The pre-existing Windows TCP listener enumeration anomaly is not claimed solved. No formal `FINAL-*` gate is changed by this candidate.
