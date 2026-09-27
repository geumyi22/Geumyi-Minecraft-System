# Version and source recovery matrix

Confirmed runtime baseline: 2026-09-26. Recovery status updated 2026-09-27.

CI:
- System CI run 36299122264: GSC, GDS and ResourcePack validation passed.
- System CI run 36304228157: follow-up run with StatusAgent JDK 21 source build completed successfully alongside GSC, GDS and ResourcePack validation.
- System CI run 36305340513: post-security-sanitization verification completed successfully; GSC, StatusAgent, GDS and ResourcePack jobs all passed.

| Component | Baseline | Path | Recovery status |
|---|---|---|---|
| GSC | 4.2.3 | GSC/ServerCenter | Recovered source; Windows Go tests covered by System CI |
| GeumyiStatusAgent | 0.5.4 | GSC/StatusAgent | Full 9-file Java source reconstruction present; JDK 21 clean build succeeds; historical deployed JAR reused older precompiled helper classes so byte-identical clean rebuild is not claimed |
| GSCM | 1.1.2+112 | GSCM | Recovered Flutter/Android source and iOS generation scripts; Android/iOS Actions succeeded |
| GST | 1.1.1 HOTFIX | Plugins/GeumyiServerTools | Exact final HOTFIX/overlay source is tracked; rebuilt overlay matched 31/31 uncompressed JAR entries. Legacy 0.1.5 core remains binary-only |
| GDS | 1.1.1 | Plugins/GeumyiDiscordStatus | Recovered full plugin source, stubs and tests; JDK 21 CI passes |
| GeumyiTechnology | 0.1.3 | Plugins/GeumyiTechnology | Reconstructed source tree is tracked; built from preserved 0.1.0 source + compatibility artifacts + deployed 0.1.3 JAR; semantic bytecode/resource comparison completed; not labeled untouched original source |
| GeumyiChemistry | 0.4.1 | Plugins/GeumyiChemistry | Reconstructed source tree is tracked; built from preserved 0.4.0 source + deployed 0.4.1 JAR; semantic bytecode/resource comparison completed; not labeled untouched original source |
| Wild server | Paper 26.3 | Servers/Wild | 2026-09-27 live E2E evidence captured; sanitized current server.properties tracked; GSC/GST/GDS runtime healthy; Bedrock/Geyser excluded as separate known issue |
| Playground server | Paper 26.3 | Servers/Playground | 2026-09-27 live E2E evidence captured; sanitized current server.properties tracked; GSC/GST/GDS runtime healthy; AutoSaveWorld RegionFileCache issue is non-blocking follow-up; Bedrock/Geyser excluded |
| Resource packs | Java 26.3 / bundled Bedrock | ResourcePacks | Recovered expanded assets and Wild Geyser mapping; JSON/metadata CI passes |

## Public repository note

The repository is now public. Current tracked/recovered material was reviewed for common credential and personal-information patterns; see `SECURITY-NOTES.md`. Git-history metadata and a deleted historical share URL have separate caveats documented there.

## Day-4 live verification

See `DAY4-E2E-REPORT.md` for the 2026-09-27 live server-PC verification, user-approved exclusions and non-blocking follow-ups.
