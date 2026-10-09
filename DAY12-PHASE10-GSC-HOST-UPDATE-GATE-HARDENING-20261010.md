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

## Conditions before asking operator for real Server-PC Host upgrade

1. Completed Windows test suite and separate reproducible Host **versioned** prerelease build; do not stamp changed Host source as `4.3.9-rc.2` or overwrite previously verified/signed rc2 artifacts.
2. Disposable Host-service upgrade and rollback validation, including wrong-version listener rejection, service recovery, own GSC Client sessions, official 4.3.8 Host backup exact SHA, and no changes to Minecraft backends/Golden checkpoints.
3. Updated pinned manifest signature, code signing constraints, preflight and explicit rollback procedure. The operator's previous permission for general repository work or a **SubPC CLIENT-only** test is NOT permission for an actual Server-PC Host restart.
4. Dedicated real network isolation proof remains separately required. Windows OS IPv4 **and** IPv6 listener/owner attribution for the eight protected ports is NOT validated by GSC's preventive on-disk server.properties guard, disposable CI, firewall-Allow metadata or this update helper.
5. No extra real SubPC scans/installs or repeated WFP/TCP snapshots just to duplicate the PASS data.

**Current canonical status:** SubPC Client-only Canary real read E2E **PASS**; GSC Host prerelease verification **pending CI**; production `backend_ports_private=FAIL`; Day12.11 full E2E, 12.12 soak, 12.13 Stable **BLOCKED**.
