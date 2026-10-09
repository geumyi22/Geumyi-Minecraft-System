# Geumyi Day 1–12 Windows PC temporary cleanup — operator guide

Updated: 2026-10-09. Tooling prepared; **not executed on the user's PCs**.

## Why this is not an automatic "delete everything" command

The Day 1–12 project generated short-lived Git checkouts, stage directories, Android/iOS build scratch space and read-only diagnostic reports. It **also** generated production worlds, GSC state/configuration, backups, Golden checkpoints, cache, recovery evidence, rollback tooling, JAR packages and Day 12 evidence. Those may share generic words like `Day10`, `Geumyi`, `backup` and `temp` and must **never be removed by a broad name match**.

**Day 12 is still IN PROGRESS**. The last confirmed production canonical verifier was 18 PASS / 0 WARN / 1 FAIL (`backend_ports_private`), and final Java/Bedrock/GSCM E2E, offline startup and soak are pending. Cleaning temporary files **does not close or alter final gates**.

## One entrypoint — operator PC / server PC

Download the [Day 12 Operator Kit](https://github.com/geumyi22/Geumyi-Minecraft-System/actions/workflows/day12-operator-kit.yml) for the latest `main` commit, extract it, and double-click:

`tools\day12\Geumyi_Day1To12_PC_Temp_Cleanup.cmd`

Do **not** run it as administrator for normal user temporary files. Running it on the server PC is possible, but for minimal operational impact use Preview first, and do not run Quarantine while a Day 1–11 maintenance or test task is running. On a separate client PC, it can only inspect files on **that** PC; it does not clean across the network.

### Menu options

1. **Preview** — the only default action; scans the current Windows user's `TEMP`, `TMP`, and `%LOCALAPPDATA%\Temp` at their immediate child level for recognized Day 1–12 workfolder name patterns. Desktop and Downloads are **inventory-only**. Returns a sanitized `Day1To12-Cleanup-Preview-*.json`, plus a **private local** plan (contains original paths).
2. **Quarantine** — requires a Preview plan made within 24 hours and the literal approval phrase `QUARANTINE_GEUMYI_TEMP`. Rechecks that each candidate is unchanged, is a top-level known temporary directory, is at least **7 days old** (configurable 3–3650 from direct PowerShell invocation), has no protected contents, no reparse/junction, and is on the same volume as local quarantine. Moves eligible folders to `%LOCALAPPDATA%\Geumyi-Day1To12-Cleanup\Quarantine\<RunId>`, with a crash-recovery manifest. Nothing is permanently deleted in this step.
3. **Restore** — requires a RunId and literal `RESTORE_GEUMYI_TEMP`, never overwrites an existing source path; recovers quarantined directories to their original TEMP locations.
4. **Purge** — after **at least 14 days in quarantine**, requires a RunId and `PURGE_GEUMYI_QUARANTINE_14D`. Permanently deletes **only items still inside that RunId's local quarantine directory**, not production or unknown paths, and leaves the audit manifest.

### Protective holds / deliberate limitations

- **Day 12 records are identified but quarantining them is blocked** until a later, evidence-based final closure. The tool does not claim Day 12 final completion or infer that old reports are unneeded.
- **Days 1–7** are eligible only when they use the explicit recognized `Geumyi-DayN-...` temp naming scheme. The tool cannot reliably identify unnamed, randomly named folders from historic sessions. Missing an item is safer than deleting an unrelated file.
- Day 8–11 include names grounded in the project's observed Windows TEMP launcher/scripts, such as `Geumyi-Day8-...`, `Day9-Final...`, `Day10-Stage...`, `Geumyi-Day11-...`. Unknown names and generic Windows temporary files are ignored.
- Older GSCM Flutter-generated scratch folders can be listed but **always held for manual review**. APK/IPA releases, JARs and installer packages are preserved rather than being treated as disposable.
- Anything containing world/region/player data, backups, Golden, cache, recovery/rollback, logs/crash dumps, configuration, databases, signing keys, secrets, plugins/mods/JARs, or `.git` is held; so are oversized (>1 GiB), >10,000-item, too-recent, changing or junction/reparse-point trees.
- **Never touches** `C:\ProgramData\GeumyiServerCenter`, actual Minecraft server directories/worlds, Windows Update/Prefetch, Recycle Bin, installed apps, GitHub repositories outside accepted TEMP children, or any user personal files on Desktop/Downloads.
- Quarantining does not immediately free meaningful disk space: the data remains on the same volume so it can be restored. Disk space is reclaimed only after the separately approved 14-day Purge. No silent permanent deletion.
- Local private plan/manifest files include absolute paths solely for safe recovery. **Do not upload** `plan-*.json` or `manifest.json` to a public repository. The generated Preview/Quarantine report excludes original paths.
- This utility is **standalone safety tooling**, not Day 12 E2E closure. Do not edit `FINAL-RELEASE-GATES.json` or Stable status because a cleanup run succeeded.

## Validation status

- GitHub Operator Kit PowerShell parser + packaging: CI required.
- Day 1–12 name allowlist and protected-object regression: `-Synthetic` classification mode.
- Windows CI fixture: isolated old Day 6 scratch directory is previewed, quarantined and restored; protected `world` folder and Day 12 item remain untouched. This is **synthetic CI**, not a scan of the user's actual PC.
- Require the corresponding latest GitHub Actions results to be PASS before using any mutation menu command; failed tests are blockers.

## Recommended immediate usage

On the user's PC run **menu option 1 (Preview)** only. Inspect sanitized summary and supply it for review. With Day 12 unfinished, avoid quarantining anything required for ongoing evidence or next-day diagnostics. User approval and a reviewable plan are required before moving any candidate.
