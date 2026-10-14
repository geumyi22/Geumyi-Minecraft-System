# Day12 recovery destination and consistency plan v5 — 2026-10-15

PR #53 remains Draft. This stage plans destinations and checks existing directory metadata. It does not create a backup, upload, stop/update a server, change synchronization, enumerate world trees, or modify final release gates.

## Accepted actual evidence

The operator's v4 report generated `2026-10-13T17:05:20.5020770Z` (2026-10-14 02:05:20 KST) has SHA256 `496b7730b25b5b70abf551c5349cd7163c29c7e73163f15231092edbfbfd77c6`. It found the three expected online source roots, the Other root, config/API agreement and an accessible OneDrive path matching discovery. All server roots and OneDrive had reparse attributes. Reparse attributes alone do not identify a junction: cloud placeholders can also be reparse objects. The operator then explicitly confirmed the original server folders are inside OneDrive.

The sole v4 reason `LEXICAL_DESTINATION_OVERLAP` compared originals against the whole provider container selected by the UI. This correctly identified containment but did not distinguish it from overlap with an actual future archive. Source containment is now an observation; actual proposed archive destinations receive separate comparisons. No data loss was established or assessed.

The previous backup was deleted. No existing recoverable asset, synchronized cloud copy, independent download or tested restoration is inferred from this evidence.

**Actual v5 metadata plan:** generated `2026-10-14T17:09:27.6109695Z` (2026-10-15 02:09:27 KST), SHA256 `af8e9a7e49d6d17b41f52f0a4e05d0c538f2231d7ee5ad2be199da792c92714a`. Result `PLAN_PATHS_REVIEW_REQUIRED`, no plan reason codes: active roots 3/3, GSC state included, all three candidates `PLANNED_NOT_CREATED`, no destination overlap observed, normalized metadata comparisons available. All four original role roots are within OneDrive in both lexical and normalized metadata comparisons. Local staging is separate from both provider containers. The G: mount and sole discovered OneDrive container are used as **unverified intended-provider planning candidates**, not account/ownership proof. G: again reports FAT32; actual backing/large-file enforcement remains unverified. The original report remains local and is not committed. No live source or cloud data was changed; snapshot, capacity, encryption, cloud transfer, restore and release gates remain false.

## Destination model and read-only implementation

| Item | Planned purpose | Required relationship |
|---|---|---|
| Existing OneDrive container | Observe source placement and propose a sibling archive location | A source inside the container is recorded, without treating that whole container as a new backup |
| Proposed OneDrive archive leaf | New immutable encrypted archive parts | Outside every configured/API source, GSC state, Google archive and staging location |
| Referenced G: mount / explicitly selected Google parent | Intended Google location, provider/account remains unverified | Never identify a system child folder as the provider account; check only selected/root metadata |
| Proposed Google archive leaf | Independent intended-provider copy | Outside every source/GSC state and both other destinations |
| Proposed local staging leaf | Snapshot/encryption work location | Outside all source/GSC state and both entire provider containers |

The tool generates fresh application-controlled candidate names and checks exact metadata. Existing file/folder candidates are refused. Missing candidates are `PLANNED_NOT_CREATED`; **none are created, reserved or tested for write access**. OS-selected paths are treated as literal names, so `$` or `%` inside a folder name is not a config environment expression. The config resolver retains the source-backed v4 expression semantics.

Existing directories are opened with zero desired access, full sharing and `OPEN_EXISTING`, using directory and no-recall flags. The normalized NT name is queried for alias comparisons. No data-read handle or privilege enablement is requested. Microsoft documents metadata-only zero-access handles in [CreateFileW](https://learn.microsoft.com/en-us/windows/win32/api/fileapi/nf-fileapi-createfilew), directory handles in [Directory Handles](https://learn.microsoft.com/en-us/windows/win32/fileio/obtaining-a-handle-to-a-directory), and normalized NT names in [GetFinalPathNameByHandleW](https://learn.microsoft.com/en-us/windows/win32/api/fileapi/nf-fileapi-getfinalpathnamebyhandlew). These names identify current directory metadata; they do not prove provider identity, upload state or future-write safety.

For an absent leaf, the existing parent's normalized name is projected with the fixed new leaf. Every config/API source is compared conservatively, including divergent paths. Missing comparison records, missing Other/GSC state scope, unknown normalized names, equal/ancestor/descendant destinations, and staging inside a provider remain blocked. Report output itself must also be separate from known originals and provider containers. The planner never enumerates G: children or world directories.

`PLAN_PATHS_REVIEW_REQUIRED` means the directory layout can be reviewed, **not execution permission**. `physical_overlap_verified=false` remains because leaves are uncreated/unreserved, files beneath sources have not been inventoried, and aliases can change before a future operation. All checks must be repeated at the actual approved write boundary.

## Consistent full recovery scope

| Role | Operator expectation | Future consistency boundary |
|---|---|---|
| Wild | ONLINE | Verified graceful offline state or independently proven application-consistent snapshot |
| Playground | ONLINE | Same, with its update-policy/offline-start gates retained |
| Lobby | ONLINE | Same, including exact plugins and associated proxy/shared-state configuration |
| Other | Intentionally OFFLINE | Keep offline; verify no relevant writer without starting it |
| GSC and common state | Management state | Identify writers and consistent config/device/credential/version capture, privately encrypted |

The default future full-backup method is an explicitly approved graceful offline boundary. A proven application-consistent snapshot is an alternative only after its storage, writer coordination and recovery behavior are demonstrated. Absence of a listening port alone is insufficient writer evidence. Cross-server/plugin/external database state must have an identified consistency boundary before separate role snapshots are called one network checkpoint.

Source inspection found that GSC `v4_backup.go` performs source sizing/ZIP traversal and directory/archive creation. `full` rejects a listening Java port; `world` invokes `save-off`, `save-all flush` and best-effort deferred `save-on`. `GeumyiTechnology.java` independently schedules state saves every 60 seconds and on plugin shutdown; `MachineStore.java` writes machine data. World-save commands do not coordinate that separate plugin task. Therefore the existing online world ZIP does not establish full application consistency.

The current GSC archive is a plain ZIP with an absolute source path in its internal manifest. Creation computes a SHA256 and returns `Verified=true`; this is not proof of encryption, provider upload, independent download/extraction or restore. Its disk guard uses system-drive space, which may differ from the archive location, and its destination is GSC's configured backup area rather than the cloud paths in this plan. **No existing GSC backup endpoint is called by v5.**

## Concrete future execution sequence — not executed or authorized here

1. Privately inventory the complete source/placeholder/reparse/external-storage and cross-server scope under separate approved work. Measure source size and actual staging/cache needs; verify each provider's remaining quota. G: Windows-reported FAT32/volume free space must not become a cloud quota or proven file-limit claim.
2. Select and verify archive encryption, private password/key entry and independent key recovery. Do not put credentials in scripts, command lines, reports, repository files or public archives. Prefer encrypted bounded parts below 4GiB when actual large-file support remains unverified, but validate the archive/reassembly/restore design before real data.
3. Approve a concrete writer/consistency boundary and maintenance scope. Verify graceful completion and no restart/automation writer, or prove the application-consistent snapshot method. Keep Other offline. Do not keep saves disabled during a slow cloud upload.
4. Revalidate/reserve new destinations only in that authorized execution stage; protect originals and refuse existing destination reuse. Create the private consistent encrypted archive, hash it, and retain an immutable snapshot identity and recoverable version/config map.
5. Resume only according to the approved lifecycle procedure. Upload immutable encrypted parts asynchronously; confirm each provider completed upload. A OneDrive sibling shares an account/volume failure domain, so it is not the independent second copy by itself.
6. Independently download, compare hashes, decrypt and restore to an isolated disposable location. Verify actual GSC/Paper/plugin recovery without overwriting originals; protect the new proven archive before release/ACL/canary work.

The machine-readable execution blockers are consistency, encryption, local/cloud capacity, account/sync, placeholder/external state, cross-server shared state, independent restore and authorization. Backup/upload/restore/Stable flags remain false even when directory comparisons are available. `FINAL-RELEASE-GATES.json` is unchanged and blocked.

## Tests, artifact and operator burden

The Windows fixture suite covers OneDrive-contained sources with separate sibling destinations, real junction aliases, unknown metadata, all source-record completeness checks, missing GSC state, equal/nested/provider/staging overlap, prefix/case/slash boundaries, missing/invalid/existing/denied candidates, literal path characters, safe report output and private-data exclusion. Original and existing-candidate hashes stay unchanged; all candidate directories stay absent. AST checks prohibit production folder enumeration and source mutations and permit writes only in the report emitter.

Windows CI tests PowerShell 5.1 and 7, the quiet single-CMD self-test, hosted-runner BLOCKED behavior, and exact-head ZIP contents/hashes. `BUILD-INFO-V5.json` identifies the tested PR head. A prior-head PASS is insufficient for delivery. Do not rerun v3 or v4. Where this chat can access the already-confirmed server PC, execute v5 metadata checks directly and deliver its sanitized result; the operator should not be asked to repeat the same inspection. The v5 CMD is retained for another host or future reproduction, not a request to create/upload/restore a backup.
