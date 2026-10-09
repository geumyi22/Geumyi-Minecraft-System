# Day 12.10 — Production GSC Host update gate hardening (repository-only, not deployed)

**Context:** The secondary PC **GSC 4.3.9-rc.2 CLIENT-only** actual update / runtime / authenticated Host status chain is fully **PASS**, through real evidence at 06:37:35 KST. **The production GSC Host remains 4.3.8.** Its eight private Java/RCON ports still fail mandatory proof, hence **NO live Host release or Stable gate transition**.

## Source flaw discovered in Host self-update

Before this change, `GSC/ServerCenter/cmd/setup/selfupdate_windows.go` implemented `waitGSCHealth(35s)` by querying `http://127.0.0.1:8787/api/health` and returning success for **any HTTP 2xx**. This is insufficient evidence that the **new** version actually replaced the **old** Host; an old/stale service listener could satisfy that response.

The same helper's `restoreSelfUpdateFiles` discarded copy/remove errors but set `report.rolled_back=true`, which could misreport recovery when the original GSC executables were not restored. The updater also calls `closeGSCClientForUpdate()` (graceful taskkill, then force if required) **on the same Host PC** before restarting only the GSC Host service. This may interrupt GSC Client sessions locally and must be disclosed before asking for a live Host maintenance window.

## Repository-only mitigations

- Candidate Host health now requires **HTTP 200, GSC `ok=true`, `generation=4` and `version` equal to the exact Setup target**. Stale `4.3.8` health cannot be accepted as proof that `4.3.9-rc.x` actually started.
- In a rollback, require at least a returning *GSC-v4 positive health envelope*, not just HTTP 2xx; the rollback check deliberately does **not** hardcode 4.3.8 because future upgrades may roll back to other previously installed versions. Stronger original-version binding remains a future safety improvement.
- `restoreSelfUpdateFiles` returns an error if any expected file restoration/deletion failed. The rollback report is `rollback_failed` rather than `rolled_back` when restoration fails or recovered Host service restart/health is not verified. Continue attempting remaining recoverable files after an individual failure; do not leak absolute paths in the bounded restore error.
- Added **Windows Go unit tests** (`GSC/ServerCenter/cmd/setup/selfupdate_health_windows_test.go`) to reject unrelated/mismatched GSC Host Health responses, accept only exact candidate version, verify the empty-expected rollback envelope, and test successful/missing-backup multi-file restoration.
- These patches are part of future source; they **are not in the previously generated signed GSC 4.3.9-rc.2 Client operator ZIP or running production 4.3.8 Host**, and they do not retroactively upgrade an old Host or prove the mandatory private-port gate.

## Review / CI status

Source changes: `GSC/ServerCenter/cmd/setup/selfupdate_windows.go` and `GSC/ServerCenter/cmd/setup/selfupdate_health_windows_test.go`. Newest Source CI run `37994995744` and Host Test `37994995746` were initiated; **conclusion pending review**. Never label new update/rollback code tested on a real Host until an isolated **HOST-service** Windows transaction and recovery test is carried out and operator approves a maintenance window.

## Verified separate Host RC3 preview — 2026-10-10

- Isolated Host **4.3.9-rc.3** (distinct from the real SubPC Client `4.3.9-rc.2`) [GitHub Actions `37995231947`](https://github.com/geumyi22/Geumyi-Minecraft-System/actions/runs/37995231947) **SUCCESS**, source commit `f45f1ba58171cd8018b6c74d2a0ca8bafe1b47e0`. Reused complete baseline System CI, rebuilt version-stamped Host/Client/Setup in **disposable Windows CI**, ran Go tests and Host non-destructive Day10 selftest; original main's `4.3.8` version stamps untouched.
- Downloaded actual artifact `gsc-4.3.9-rc.3-UNSIGNED-DO-NOT-INSTALL` (ID `11647186030`) and verified **ZIP CRC PASS**, six members, SHA256SUMS **5/5 MATCH**, metadata `candidate_version=4.3.9-rc.3`, `source_commit=f45f1ba58171cd8018b6c74d2a0ca8bafe1b47e0`, `unsigned=true`, `review_only=true`, `operator_install_approved=false`, `production_host_modified=false`, `stable_published=false`, `backend_ports_private=UNCHANGED_FAIL`. Outer ZIP SHA-256 **`5df82eb32411cfb27bc2f707d1d8286210c3a68d8bcb4247907c364bdcd82250`**.
- **Do not install** this unsigned preview. The updated Host replacement/rollback has source tests and build validation, **NOT** a completed real Windows Host-service stop/replace/start/rollback transaction; that separate disposable-service E2E is still required before any production maintenance recommendation. Client-only SubPC rc2 remains untouched and has already completed real authenticated read E2E PASS.
- Production Host 4.3.8, Paper/Velocity/RCON/worlds/firewall, protected Golden 4/4 remain unchanged. This preview **does not** close the OS native eight-port IPv4+IPv6 address/owner bind security gate. Stable blocked.

## Conditions before asking operator for real Server-PC Host upgrade

1. Completed Windows test suite and separate reproducible Host **versioned** prerelease build; do not stamp changed Host source as `4.3.9-rc.2` or overwrite previously verified/signed rc2 artifacts.
2. Disposable Host-service upgrade and rollback validation, including wrong-version listener rejection, service recovery, own GSC Client sessions, official 4.3.8 Host backup exact SHA, and no changes to Minecraft backends/Golden checkpoints.
3. Updated pinned manifest signature, code signing constraints, preflight and explicit rollback procedure. The operator's previous permission for general repository work or a **SubPC CLIENT-only** test is NOT permission for an actual Server-PC Host restart.
4. Dedicated real network isolation proof remains separately required. Windows OS IPv4 **and** IPv6 listener/owner attribution for the eight protected ports is NOT validated by GSC's preventive on-disk server.properties guard, disposable CI, firewall-Allow metadata or this update helper.
5. No extra real SubPC scans/installs or repeated WFP/TCP snapshots just to duplicate the PASS data.

**Current canonical status:** SubPC Client-only Canary real read E2E **PASS**; GSC Host prerelease verification **pending CI**; production `backend_ports_private=FAIL`; Day12.11 full E2E, 12.12 soak, 12.13 Stable **BLOCKED**.
