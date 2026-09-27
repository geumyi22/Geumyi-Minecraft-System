# Version and source recovery matrix

Confirmed runtime baseline: 2026-09-26. Recovery status updated 2026-09-27.

CI:
- System CI run 36299122264: GSC, GDS and ResourcePack validation passed.
- System CI run 36304228157: follow-up run with StatusAgent source build (see Actions; final completion recorded after Day-3 sync).

| Component | Baseline | Path | Recovery status |
|---|---|---|---|
| GSC | 4.2.3 | GSC/ServerCenter | Recovered source; Windows Go tests covered by System CI |
| GeumyiStatusAgent | 0.5.4 | GSC/StatusAgent | Full 9-file Java source reconstruction present; JDK 21 clean build succeeds; historical deployed JAR reused older precompiled helper classes so byte-identical clean rebuild is not claimed |
| GSCM | 1.1.2+112 | GSCM | Recovered Flutter/Android source and iOS generation scripts; Android/iOS Actions succeeded |
| GST | 1.1.1 HOTFIX | Plugins/GeumyiServerTools | Exact final HOTFIX/overlay delta recovered; rebuilt overlay matched 31/31 uncompressed JAR entries. Legacy 0.1.5 core remains binary-only |
| GDS | 1.1.1 | Plugins/GeumyiDiscordStatus | Recovered full plugin source, stubs and tests; JDK 21 CI passes |
| GeumyiTechnology | 0.1.3 | Plugins/GeumyiTechnology | Reconstructed from preserved 0.1.0 source + compatibility artifacts + deployed 0.1.3 JAR; semantic bytecode/resource comparison completed; not labeled untouched original source |
| GeumyiChemistry | 0.4.1 | Plugins/GeumyiChemistry | Reconstructed from preserved 0.4.0 source + deployed 0.4.1 JAR; semantic bytecode/resource comparison completed; not labeled untouched original source |
| Wild server | Paper 26.3 | Servers/Wild | Paper provenance + sanitized 2026-09-10 server.properties evidence recovered; exact 2026-09-26 live config still requires capture from server PC |
| Playground server | Paper 26.3 | Servers/Playground | Paper provenance + sanitized 2026-09-10 server.properties evidence recovered; exact 2026-09-26 live config still requires capture from server PC |
| Resource packs | Java 26.3 / bundled Bedrock | ResourcePacks | Recovered expanded assets and Wild Geyser mapping; JSON/metadata CI passes |

## Public repository note

The repository is now public. Current tracked/recovered material was reviewed for common credential and personal-information patterns; see `SECURITY-NOTES.md`. Git-history metadata and a deleted historical share URL have separate caveats documented there.
