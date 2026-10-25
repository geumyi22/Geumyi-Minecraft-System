# Day12 Security Integration — PR #47–#52 (2026-10-12)

> **REVIEW / CI ONLY** — no production apply, merge, release or server/world/backup/ACL mutation is authorized by this document.
> Integration branch: `integration/day12-security-review-20261012` (single-parent squashed tree against `main`).

## Fixed source provenance and conflict resolution

| Change | Reviewed source | Integration decision |
| --- | --- | --- |
| #47 | `3592b29dc3a3d19009fd82435b68a2c0cc85826c` | Included once through PR #52 tree |
| #48 | `50129f0f1bda08c39d4c648136b40a54f5bc897c` | ORIGINAL `cmd/host/loopback_guard.go` blob `de98a07095b4a3d9f2f8057364f165f5be8d72a2` selected exactly once |
| #49 | `70e6fea27fc39e31f823744d6971a5db53d85759` | Included once through PR #52 tree; keep PowerShell self-test hardening |
| #50 | `c47b9339214a9af8391ba238c0fab8b1d8805f64` | Included once: read-only unauthenticated loopback, scoped Agent token, local Client session |
| #52 | `06536fa2230c679988773249cc7a5f50574bc368` | Selected tree: standard-user ACL negative test, Windows file replacement ACL checks |

**Merge strategy:** do NOT independently merge #47, #48, #49, #50 or #52. Their Git histories overlap and PR #48 adds the same loopback guard as #49. The integration branch preserves the *source code*, not their redundant commit graph. Preserve the PR #52 loopback regression tests (they reflect the stricter PR #50 read-only policy). The PR #48 guard and PR #52 guard have the same observable conditions; comments and variable names differ. Historical PRs stay Draft pending integration disposition.

**Provenance**: `main` before integration `0d765f9897066ee2388bca9e98a390f3b2d331a9`; PR #52 tree `87610c790c155800506743bbf8e84f64fc5cf395`.

## Additional CI evidence hardening on integration branch

1. `.github/workflows/system-ci.yml`: Windows job reruns both ACL-specific `atomicfile` tests with `go test -v -count=1`, requires an explicit `--- PASS:` record for *each* test and rejects every `SKIP` / `UNVERIFIED`. Normal `go test ./...` can succeed even when Go tests call `t.Skip`, so success alone was not sufficient evidence.
2. `.github/workflows/day12-safety-ci.yml`: always retains the disposable standard-user negative-test **result JSON** as an artifact to permit independent verification. All test paths are synthetic Windows runner fixtures.
3. The `tools/day12/ci/Day12_ACL_NegativeTest_Windows_CI.ps1` test requires an independent standard user via LogonUser + RunImpersonated, checks the risky create right and then denied create/modify/replace after ACL narrowing; this is NOT a live host test.

**Prior checked evidence**: PR #52 (`06536fa`) had five GitHub workflow runs reporting SUCCESS; original read-only safety job log explicitly contained `NEGATIVE TEST STATUS: PASS`. **Integration-branch CI must be verified separately** after opening its Draft PR. No CI is evidence of complete production safety.

## Current risks and explicit limits

- **HIGH/PENDING live verification:** actual inherited BUILTIN\\Users directory create rights, effective standard-user access, integrity levels, per-object owner, reparse children, service account identity and rollback equivalence. `icacls /save` captures DACL for /restore, not an exact owner/SACL/MIC snapshot.
- Windows `os.Chmod(0600)` does not configure a restrictive Windows NTFS DACL. Random exclusive temp names prevent fixed-name pre-planting, but **do not replace a least-privilege directory DACL**.
- The atomicfile Windows fixture compares DACL protection and inheritance marker. Owner is *observed in logs*, not a proof of owner-equivalence with a separately-created standard-user file; state this precisely.
- Review of `JWT` finding: no supporting JWT implementation was identified in reviewed GSC bearer-token path; do not implement JWT-secret changes without evidence.
- Short IPv4 spelling (`127.1`) is not parsed by `net.ParseIP` in loopback guard. Supported canonical loopback names/literals are `localhost`, `127.0.0.1`, and `[::1]`; do not add permissive parsing merely for shorthand compatibility.
- Local Client proxy / dashboard, StatusAgent token creation and reconfiguration, GSCM and third-party local operator write scripts require **on-device compatibility/E2E**; do not claim full compatibility based on CI.
- StatusAgent `agent.properties` contains a scoped operational credential. The file's effective ACL still needs an on-host check; never upload its contents or any real private ACL dump.

## Gates — ALL required before production

- [ ] **Integration CI**: 5 workflows successful, Windows named ACL tests explicitly executed (no skip), published synthetic negative-test JSON reviewed.
- [ ] Independent diff and security regression review for PR #48 overlap / #50 token and client session model.
- [ ] On-host **READ-ONLY**, authorized private evidence collection: target ACE/SID/owner/integrity/reparse inventory; redact credentials and private DACL evidence before sharing.
- [ ] Reproducible disposable-tree DACL backup/restore with matching intended security descriptor scope; independent standard-user negative and Host/Agent/updater positive permission checks.
- [ ] Explicit operator approval for a scoped production change, exact target list, user-recoverable rollback, service sequencing and live E2E. **No approval implied here.**
- [ ] Only then consider resolving old Draft PRs and a reviewed merge/release.

**Operator action now:** none. Keep real host, server, worlds, backups, DACL, firewall and services unchanged.
