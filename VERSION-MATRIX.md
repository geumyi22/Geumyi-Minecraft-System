# Version and source recovery matrix

Confirmed target baseline: 2026-09-26. Version does not imply complete source recovery.

| Component | Baseline | Path | Recovery status |
|---|---|---|---|
| GSC | 4.2.3 | GSC/ServerCenter | Recovered source; installer JAR payloads supplied from Releases |
| GeumyiStatusAgent | 0.5.4 | GSC/StatusAgent | Partial overlay (4 Java files); helper source not yet recovered |
| GSCM | 1.1.2+112 | GSCM | Recovered Flutter/Android source and iOS generation scripts |
| GST | 1.1.1 HOTFIX | Plugins/GeumyiServerTools | source not yet recovered for exact HOTFIX |
| GDS | 1.1.1 | Plugins/GeumyiDiscordStatus | Recovered full plugin source, stubs and tests |
| GeumyiTechnology | 0.1.3 | Plugins/GeumyiTechnology | source not yet recovered |
| GeumyiChemistry | 0.4.1 | Plugins/GeumyiChemistry | source not yet recovered |
| Wild server | Paper 26.3 | Servers/Wild | Paper provenance recovered; current operational configuration source not yet recovered |
| Playground server | Paper 26.3 | Servers/Playground | Paper provenance recovered; current operational configuration source not yet recovered |
| Resource packs | Java 26.3 / bundled Bedrock | ResourcePacks | Recovered expanded assets and Wild Geyser mapping |
