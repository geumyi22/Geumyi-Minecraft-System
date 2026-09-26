# Recovery report — 2026-09-26

## Evidence

- Downloaded MC_LATEST_2026-09-26_v3_FINAL.zip SHA-256: 8d7baf85367a740f6fe6d5298dc4ae246fe311b5826af3ce6d5aa9cb495b13f9, identical to the existing GitHub Release digest.
- GSC source and Agent overlay recovered from its nested FINAL/source bundles.
- GSCM recovered from the repository's decoded gscm-ios-source.b64 at commit 25d42c685287a94312b35d83f4890b1743bdaf08, cross-checked against the CLEAN Android builder. Dart app/tests match byte-for-byte before the documented fixture sanitization. The two Android Gradle files differed; the existing successful Actions compatibility configuration was retained as canonical.
- GDS 1.1.1 source downloaded directly from ChatGPT Library; its companion hotfix bundle's GDS binary hash matches the current Release.
- Library searches covered Geumyi, GeumyiServerTools, GeumyiDiscordStatus, GeumyiTechnology, GeumyiChemistry, GeumyiStatusAgent, HOTFIX, Wild, Playground, 야생 and 놀이터.
- Prior referenced chat was read; its exposed turns contained the target/version checklist and no attachments.

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

## Exclusions and limitations

GST's available source predates the current HOTFIX and depends on an old binary base. Agent's source is an overlay, with five helper sources missing; its original base dependency remains obtainable inside the existing Release archive. Older Technology/Chemistry sources were not promoted. The older local/web RCON server manager was not substituted for the current GSC deployment.

GSC installer compilation requires release JAR payloads. The source importer does not operate or reconfigure live Minecraft servers or install mobile builds. Required cross-platform resource assets are kept in each pack; identical assets use the same Git blob.

## Verification

- GSC: recovered Go unit tests passed on Windows (host, setup and Java runtime packages).
- GDS: compilation on JDK with --release 21 and all 28 existing core tests passed.
- Source security review: see SECURITY-NOTES.md; two Gitleaks findings are reviewed synthetic fixtures, no real credentials detected.
- GSCM Android: [run 36233789439](https://github.com/geumyi22/Geumyi-Minecraft-System/actions/runs/36233789439) succeeded, including analyze, tests and APK artifact generation.
- GSCM iOS: [run 36233789513](https://github.com/geumyi22/Geumyi-Minecraft-System/actions/runs/36233789513) succeeded, including unsigned IPA artifact generation.
- Both CI runs tested source-import commit 6424982e9c290d439a35207112dd7fd4a868ee36. Subsequent verification updates affect documentation/manifest and restore unrelated release files byte-for-byte; mobile source/workflow blobs stay unchanged.
- Resource pack JSON and asset integrity are checked before upload.

SOURCE-MANIFEST.json lists final paths, hashes and provenance. Release assets remain unchanged.

Language JSON normalization: 31 BACAP language files contained hash comments; comments and author credits are preserved in ResourcePacks/Wild/LANGUAGE-COMMENTS.md. Raw string control characters were escaped and one misplaced quote pair in zh_tw was corrected. Translation text was not rewritten. All 488 JSON/pack metadata files then parsed successfully.

Final tracked tree: 1,211 files, including 1,016 resource-pack files; SOURCE-MANIFEST.json covers every other tracked path. All staged Git blobs were matched to the validated local files. The existing 15 release assets retain the same IDs, sizes and digests.
