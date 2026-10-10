# Day12.2 — Lobby GST / GDS exact original build found (2026-10-11 KST)

**SUCCESS: Both previously unidentified Lobby plugin files are an exact full SHA-256 match to their archived Day10 System CI JAR bytes.**

Existing `DAY10-E2E-REPORT.md` names final cutover source commit `0e1490bfe75975eb278526df0f89a430109e28d8` and System CI run `37113499031` (SUCCESS). GitHub archived `gst-1.1.1-hotfix` / `gds-1.1.1` ZIP artifacts in that run. Both ZIPs were downloaded and contained JAR bytes independently SHA256-hashed in disposable local analysis.

| Installed Lobby JAR (from private Oct09 real-server report) | Original CI artifact ID | JAR size | Full observed / official CI digest match |
|---|---:|---:|---|
| `GeumyiServerTools-1.1.1.jar` | **11271350765** | 94,488 bytes | **YES** — `ca3c07d39574d3397568ab0f125489d2ca795196bf7684943cbbdf12be2568cc` |
| `GeumyiDiscordStatus-1.1.1.jar` | **11270776846** | 77,662 bytes | **YES** — `7213acedbaf73a72ad7b3816f06c274ec5699713940d8a133f3a21bc01d37ac4` |

`tools/day10/finish_day10.ps1` intentionally renamed those CI-built GST/GDS JARs to the shorter Lobby file aliases without changing their contents. The installed files are therefore fully identified as those exact original Day10 CI artifacts, not an unknown version or inferred match based only on file size.

With the prior **11/11** non-Lobby/StatusAgent matches, the **13/13 targeted historical server-PC file digests** now match pinned GitHub CI/release content references.

**Evidence limits:** the original installed-file SHA256 readings are from **2026-10-09**; there was no new on-host file capture, loaded-class binary attestation, plugin enable test or signature validation on 2026-10-11. This resolves *historical installed JAR provenance*, not every component policy or Day12.13 Stable gate.

**No production plugins, worlds, backups, security or services were modified.** Do not redeploy currently working Lobby JARs for no reason. The strict `FINAL-RELEASE-GATES.json` remains BLOCKED pending independent 12.5 / 12.7 / 12.10 / 12.11 / 12.12 etc.

Evidence sources: [Day10 E2E report](https://github.com/geumyi22/Geumyi-Minecraft-System/blob/main/DAY10-E2E-REPORT.md), [original System CI run](https://github.com/geumyi22/Geumyi-Minecraft-System/actions/runs/37113499031).
