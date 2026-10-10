# Day 12.2 — Public artifact provenance review and two Lobby exceptions (2026-10-11 KST)

**Scope: repository reference verification COMPLETED; full fleet release-grade provenance NOT COMPLETE.** No user device, server binaries or Golden backups were changed.

## Positive evidence from actual earlier real-host report

The private on-host `Day12-Integrity-Security-20261009-061224.json` was captured on the real server PC on 2026-10-09 06:13 KST. It included SHA-256 digests of installed JARs. Its raw process/host contents and private hashes are not committed.

| Identity | Real-host matches | Reference |
|---|---:|---|
| StatusAgent 0.5.4 | **1/1** | Day 11 Secure Release CI `37627140918`, JAR and sidecar checksum matching |
| Technology 0.1.4 | **2/2** (Wild/Other) | Day 11 Secure Release CI `37627140918` |
| GST 1.1.1 HOTFIX | **3/3** (Wild/Playground/Other) | Official public release `mc-2026.09.26-v3` recorded asset SHA |
| GDS 1.1.1 | **3/3** (Wild/Playground/Other) | Official public release `mc-2026.09.26-v3` asset SHA |
| Chemistry 0.4.1 | **2/2** (Wild/Other) | Official public release `mc-2026.09.26-v3` asset SHA |

**11/11 targeted non-Lobby and StatusAgent historical file copies match pinned public CI/release references.** The three official GitHub release asset metadata values were **re-fetched on 2026-10-11** and their SHA-256, asset ID and file names matched entries in `deploy/day12-trusted-component-digests.json`: GST `590320437`, GDS `590320391`, Chemistry `590320390`. CI run `37627140918` remains the recorded source for StatusAgent and Technology. A GitHub release asset digest establishes a pinned release reference, **not a detached signature verification for the historical host binary**.

## Remaining exact exceptions

- **Lobby GST alias** `GeumyiServerTools-1.1.1.jar` had a different installed hash (94,488 B) from the v3 non-Lobby GST release.
- **Lobby GDS alias** `GeumyiDiscordStatus-1.1.1.jar` had a different installed hash (77,662 B) from v3 non-Lobby GDS.
- Day10 finalizer source `tools/day10/finish_day10.ps1` **intentionally downloads newly built System CI GST/GDS binaries and renames them to those Lobby aliases**; this explains why the Lobby file names differ. It does **not** prove which specific successful Day10 workflow invocation was used.
- Candidate historical System CI artifacts were downloaded and independently hashed for run `36915111381` and `37013810379`. The JAR sizes **match** the installed Lobby sizes, but **neither candidate's exact SHA-256 matches the old Lobby fingerprints**. These are rejected as exact provenance candidates; no false Lobby PASS.
- The original successful Day10 CI run ID or an authoritative signed manifest linking those two Lobby fingerprints to a specific build has **not** been recovered. Full `phase_12_2_component_inventory` release-grade gate remains **OPEN** until this evidence exists (or a separately approved replacement/update with verified provenance happens).

## Decision / next action

1. **Retain running files unchanged.** Do not overwrite Lobby GST/GDS with a differently hashed build based merely on identical version labels, because working Java+Bedrock function has already been user-confirmed.
2. Record **12.2 repository review as complete with two explicit provenance exceptions**; there is no justification for repeating the broad full-fleet inventory.
3. If a later strict Stable release requires zero exceptions, recover the **exact** original Day10 successful CI artifact digests or separately approve an update with preflight, backup, staging and rollback. Never fabricate release-grade provenance from filename/source intent alone.
4. Do not confuse binary file authenticity, runtime enabled plugin state, signed manifest chain, OS socket binding or 12.11 real-client E2E. They are distinct gates.

**GitHub reference ledger:** `deploy/day12-trusted-component-digests.json`. **No full Stable gate changed.**
