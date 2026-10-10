# Day 12.7 — Already-built known-good cache: bounded byte-integrity check

**Source of need:** real server-PC Day 12.7 cache Build had previously recorded **84 cached entries**; the 09:59 consolidated read-only report confirmed the manifest still had **84 entries** but did **not** rehash the actual cached files. The original requested 12.7 **offline-start recovery** E2E remains unperformed.

## Prepared tool (CI fixture verified, live unrun)

- `tools/day12/Day12_Phase7_Cache_Manifest_Integrity_READ_ONLY.ps1` and matching one-click `.cmd` run **only on the Windows SERVER PC** (GSC Host installed). No SubPC, services restart, network disconnection, cache Build, repair, copy, delete or Golden/world modification.
- Reads the exact existing `%ProgramData%\GeumyiServerCenter\ArtifactCache\known-good\day12\known-good-manifest.json`. Validates every record has a path-safe flat cache filename (reject `..` and subfolders), nonnegative size, 64-hex SHA-256 and no duplicate case-insensitive filename; refuses reparse/symlink files.
- For each manifest entry performs **read-only on-disk length and SHA256 comparison**. Outputs **counts only**, not secrets, host paths, filenames or process command lines. The count can differ from the previously observed 84 when the environment changes; it cannot automatically declare the previous 84 actually present.
- The verdict `CACHED_BYTES_HASHES_MATCH` means strictly that **every referenced cache file matched the local manifest at observation time**; the manifest is a locally stored baseline and is not itself signed here. It does not assert an official release signature, GSC Host native socket owner, or **the ability to launch with network offline**.
- Any missing file, corrupted/mismatched bytes, invalid record, duplicate or filesystem reparse target returns `CACHE_INTEGRITY_REVIEW_REQUIRED`; it never reconstructs cache automatically. Do not manually delete or update files based on that result.
- Test-only `-Synthetic` creates **temporary disposable CI fixtures only**, checks identical hashes, content tamper, traversal and duplicate entries, then cleans its own CI fixtures; no production files are mutated.

## Operator handoff — later when instructed

Download focused `day12-phase7-cache-integrity-readonly-kit` ZIP after Windows CI PASS, extract completely and run `Day12_Phase7_Cache_Manifest_Integrity_READ_ONLY.cmd` **on server PC**. Upload **only** `Desktop\Geumyi-Day12-Cache-Integrity-*\Day12-Cache-Integrity-READ-ONLY.json`. Normal unchanged server operation can continue. No need to run previously completed all-phases or LAN/Tailnet remote scans again.

If local cache hashes match, still keep 12.7 offline-start E2E OPEN. A real outage, test server restart or recovery-mode exercise must be planned separately with 4/4 Golden protection and suitable staging/rollback.

**Stable release remains blocked** by canonical `backend_ports_private`, full runtime security review, 12.11 real device E2E, 12.12 soak and remaining 12.7 offline start proof.


## 2026-10-10 — real SERVER-PC Day12.7 complete byte integrity (84/84) — NOT offline-start E2E

- **Received private real operator** `Day12-Cache-Integrity-READ-ONLY.json` from focused Windows tool (CI [`38013828430`](https://github.com/geumyi22/Geumyi-Minecraft-System/actions/runs/38013828430) success). Report `schema=1`, `phase=12.7-cached-bytes-integrity`, `synthetic=false`, `read_only=true`, `cache_modified=false`, `network_requests=0`, `manifest_valid=true`, `result=CACHED_BYTES_HASHES_MATCH`.
- **All 84/84 cached files verified SHA-256 and size** against the existing local manifest. `missing=0`, `mismatched_sha256=0`, `mismatched_size=0`, `invalid_record=0`, `duplicate_names=0`, `reparse_blocked=0`.
- Accepted scoped gate **`phase_12_7_cache_byte_integrity=PASS_REAL_HOST`**, while the *separate* mandatory **`phase_12_7_offline_known_good_startup=PENDING_LIVE`** remains OPEN. The local manifest hash check does not establish cryptographic trust of the manifest itself, GSC/Geyser/Paper boot with internet disconnected, automatic fallback, or runtime E2E.
- **No duplicate cache Build/Audit or hash check required.** Golden 4/4 remains protected, GSC Host 4.3.8 not touched, Java/Bedrock worlds not touched. Canonical `backend_ports_private=FAIL_UNVERIFIED_NATIVE_OWNER_ADDRESS`, 12.5 effective security OPEN, 12.11 live E2E and 12.12 soak OPEN, Stable/Maintenance BLOCKED.


## 2026-10-10 — GSC pre-start fail-open safety regression (disposable build only)

- Reviewed actual `GSC/ServerCenter/cmd/host/updater.go` and `lifecycle.go`. The running code's `runPreStartUpdater` returns `BlockStart=false` on non-transactional **manifest discovery/signature/local-key verification failures**, while `startServerLocked` proceeds to the original `start.bat`. There is an **intentional safety exception**: interrupted update transaction recovery that cannot complete **must block startup** to avoid booting a potentially half-updated plugin set; do not call that fail-open.
- Added `GSC/ServerCenter/cmd/host/updater_offline_prestart_test.go` to check an intentionally **missing trusted signing key** in an entirely disposable test server and explicit `hold`/`manual` update policies. These tests verify the **old JAR bytes remain unchanged**, no update is recorded applied, and the non-transactional failure does not mark `BlockStart`.
- [Day-11 Host package Go CI `38014545297`](https://github.com/geumyi22/Geumyi-Minecraft-System/actions/runs/38014545297) **SUCCESS**, and GSC Go-test job of [System CI `38014545143`](https://github.com/geumyi22/Geumyi-Minecraft-System/actions/runs/38014545143) **SUCCESS**. This is a source/disposable **signature-verification failure** test, **not** a verified real disconnected-network run, not actual GSC Host startup and not proof of real known-good Paper boot. Therefore Phase 12.7 `offline_known_good_startup` remains PENDING and Stable/Maintenance remain BLOCKED.
