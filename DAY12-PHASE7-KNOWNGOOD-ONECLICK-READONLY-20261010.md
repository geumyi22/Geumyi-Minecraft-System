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
