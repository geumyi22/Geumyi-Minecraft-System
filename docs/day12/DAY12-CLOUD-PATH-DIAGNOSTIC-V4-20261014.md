# Windows cloud path diagnostic v4 — PR #53 stays Draft

## Evidence and scope

The actual submitted v3 JSON generated `2026-10-13T16:36:43.4036640Z` (2026-10-14 01:36:43 KST) has SHA256 `c31e7aa7ac802fb26f0ed1f34a983ad586f1c80b398572e2984fc60629111897`. The original JSON and screenshots are not committed. It reports local GSC settings GET `OK`, four profiles with `GSC_SETTINGS_GET_PATH_NOT_ACCESSIBLE`, active roots 0/3, GoogleDriveFS and OneDrive processes observed, and unresolved OneDrive selection/environment matching. These are discovery failures, **not evidence of missing worlds, stopped services or data loss**. No backup/upload/restore occurred.

Explorer's Google Drive G: display of roughly 930GB capacity and 410GB free is Windows volume evidence only. It may represent an emulated volume/cache. It does not establish the Google 2TB account quota or free cloud space. The OneDrive personal Explorer namespace also does not establish an accessible filesystem folder.

Other remains intentionally OFFLINE; its actual process state is unverified here. The previous backup was deleted and is not available as a rollback asset. Final production/release gates remain BLOCKED. No server, world, backup, cloud account, service, ACL or firewall is changed by this work.

## Source inspection before implementation

At starting head `ec7e9179617f2503c6b2fbbeb80a52f934ed741f`, `GSC/ServerCenter/cmd/host/main.go`:

- `apiSettings` GET declares `ss` with JSON fields `id`, `path`, `path_file`, etc. It writes `{bind,port,...,servers:out,version}`; per-server paths belong in **`servers[]`**, not at the response root.
- Each `ss.path` is `configuredServerDir(x)`; `ss.path_file` remains the configured pointer. `configuredServerDir` gives nonempty direct `Path` precedence, otherwise reads `PathFile`, removes a UTF-8 BOM and whitespace, and expands Go `$NAME`/`${NAME}` environment references.
- `validServerDir` checks the directory and `server.properties` metadata separately from port mismatch. Existing `server_path_persistence_test.go` tests saved-path retention in the settings response.

v3 already selected `servers[].path`, but rejected all reparse directories and did not classify missing, relative, denied, unresolved-environment or pointer-specific failures. Thus the source contract alone does not explain the actual host failure; v4 collects safe distinctions. It does not assume the running binary must have the exact checked-out source behavior.

## v4 behavior

- Read the explicit/default GSC config and the fixed local GET `http://127.0.0.1:8790/api/settings` independently; config absence cannot prevent API discovery. No token lookup, authentication bypass, cookies, redirects or write methods. Response and config reads are capped at 1Mi characters and remain private in memory.
- Recognize the source-backed top-level `servers` array; explicit `data/settings/config.servers` compatibility wrappers receive distinct shape codes. Never recursively search an arbitrary response. Multiple lists, duplicate recognized IDs or conflicting accessible config/API paths remain unverified.
- Resolve direct path and path_file with Host precedence; additionally tolerate surrounding quotes, BOM and Windows `%NAME%`. Unknown environment references and relative paths receive categorical failures. **Relative Host working directory is not guessed from the config file location.**
- Read exact directory and `server.properties` metadata only. Accessible reparse/junction paths are accepted for discovery, with `final_target_verified=false`; no world enumeration, sizing, snapshot, file copy, upload or large test-file write. Lexical overlap is observed conservatively; physical overlap remains unverified.
- OneDrive candidates come from environment variables, `SHGetKnownFolderPath` with `KF_FLAG_DONT_VERIFY` (no create), User Shell Folders, immediate OneDrive Accounts `UserFolder`, OneDrive SyncRootManager `UserSyncRoots`, and the filesystem identity of the `shell:OneDrive` namespace. Namespace-only entries never become fabricated paths. Registry enumeration is bounded and never enumerates world directories.
- The operator can explicitly confirm an existing candidate by number in the local UI or browse. Confirmation and a registry match do not prove provider identity, account ownership, sync completion or quota. Candidate paths/account identifiers are never serialized.
- Query the selected Google path's reported filesystem with DriveInfo. Actual FAT32 allows at most 4,294,967,295 bytes in a single file; a DriveFS FAT32 label does not prove the backing filesystem or enforcement. The JSON requests verification before future archive work and never reports cloud quota from volume capacity/free space.
- Shared schema 2 includes `diagnostic_version:4`, categorical path/pointer/shape/selection statuses, fixed role IDs and booleans. It exports no raw paths, JSON bodies, registry names, SID, account name or exceptions. Data loss is explicitly **not assessed**. Every backup, upload, restore, provider verification and stable-release claim remains false.
- Save the share-only report under LOCALAPPDATA rather than a possibly synced Desktop. Only the report and disposable synthetic fixtures are created. The final result folder opens locally.

## Tests and artifact provenance

`Test_Cloud_Preflight_V4.ps1` exercises PowerShell 5.1 and 7 with disposable Windows directories and a real junction: percent/Go environment syntax, BOM/quoted pointers, missing/empty pointers, direct-path precedence, relative/drive-relative paths, actual Host shape, explicit wrappers, ambiguous/malformed/empty arrays, config-unavailable API fallback, API path_file, denied/duplicate/conflicting profiles, lexical overlap, missing cloud clients, mocked non-environment OneDrive discovery, namespace-only failure, and privacy sentinels. Tests verify server fixture bytes stay unchanged and inspect the diagnostic AST for recursive scans and prohibited mutations. Fixtures use no real GSC, cloud, registry or account data.

Windows CI must strictly pass both shells and a hosted-runner BLOCKED smoke test before packaging `Geumyi-Day12-GoogleDrive-OneDrive-READ-ONLY-Preflight-v4.zip`. The ZIP contains the diagnostic, CMD, Korean instructions, tests and `BUILD-INFO-V4.json` with the exact PR head SHA and hashes. CI success must be checked against the **latest** PR head before giving the operator the artifact; a prior run or synthetic PASS is insufficient. This document does not claim a run has completed or an artifact already exists.

The operator's sole next request is: extract the newly verified v4 ZIP, run `RUN_Day12_Cloud_Recovery_Preflight_READ_ONLY.cmd` once on the server PC, and send only `DAY12-CLOUD-PREFLIGHT-V4-SHARE-ONLY-THIS.json`. Do not rerun v3. No approval for backup, upload, restore, server update/restart or release is implied.
