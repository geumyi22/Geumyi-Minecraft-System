# Version and source recovery matrix

Confirmed runtime baseline: 2026-09-26. Recovery/verification status updated 2026-09-28.

CI:
- System CI run 36299122264: GSC, GDS and ResourcePack validation passed.
- System CI run 36304228157: follow-up run with StatusAgent JDK 21 source build completed successfully alongside GSC, GDS and ResourcePack validation.
- System CI run 36305340513: post-security-sanitization verification completed successfully; GSC, StatusAgent, GDS and ResourcePack jobs all passed.
- Pre-Day-6 System CI run 36344295861: GSC, StatusAgent, GDS and ResourcePack jobs all passed on the normalized preflight commit.
- Pre-Day-6 GSCM Android run 36344295867: analyze, tests, release APK build and artifact upload passed.
- Pre-Day-6 GSCM iOS run 36344295880: release no-codesign build, unsigned IPA packaging and artifact upload passed.
- Day-6 GSCM build 113 Android run 36441811005: analyze, tests, release APK build and artifact upload passed.
- Day-6 GSCM build 113 iOS run 36441810896: release no-codesign build, unsigned IPA packaging and artifact upload passed.

| Component | Baseline | Path | Recovery status |
|---|---|---|---|
| GSC | 4.2.3 | GSC/ServerCenter | Recovered source; Windows Go tests covered by System CI; Day-5 integration behavior user-verified in operation |
| GeumyiStatusAgent | 0.5.4 | GSC/StatusAgent | Full 9-file Java source reconstruction present; JDK 21 clean build succeeds; historical deployed JAR reused older precompiled helper classes so byte-identical clean rebuild is not claimed |
| GSCM | 1.1.2+113 | GSCM | Recovered Flutter/Android source and iOS generation scripts; Day-6 realtime status hotfix applied; Android/iOS CI passes; device verification in progress; stable Android release signing remains Day-8 work |
| GST | 1.1.1 HOTFIX | Plugins/GeumyiServerTools | Exact final HOTFIX/overlay source is tracked; rebuilt overlay matched 31/31 uncompressed JAR entries. Legacy 0.1.5 core remains binary-only |
| GDS | 1.1.1 | Plugins/GeumyiDiscordStatus | Recovered full plugin source, stubs and tests; JDK 21 CI passes |
| GeumyiTechnology | 0.1.3 | Plugins/GeumyiTechnology | Reconstructed source tree is tracked; built from preserved 0.1.0 source + compatibility artifacts + deployed 0.1.3 JAR; semantic bytecode/resource comparison completed; not labeled untouched original source |
| GeumyiChemistry | 0.4.1 | Plugins/GeumyiChemistry | Reconstructed source tree is tracked; built from preserved 0.4.0 source + deployed 0.4.1 JAR; semantic bytecode/resource comparison completed; not labeled untouched original source |
| Wild server | Paper 26.3 | Servers/Wild | 2026-09-27 live E2E evidence captured; sanitized current server.properties tracked; GSC/GST/GDS runtime healthy; Day-4 milestone closed |
| Playground server | Paper 26.3 | Servers/Playground | 2026-09-27 live E2E evidence captured; sanitized current server.properties tracked; GSC/GST/GDS runtime healthy; Day-4 milestone closed |
| Resource packs | Java 26.3 / bundled Bedrock | ResourcePacks | Recovered expanded assets and Wild Geyser mapping; JSON/metadata CI passes |

## Public repository note

The repository is now public. Current tracked/recovered material was reviewed for common credential and personal-information patterns; see `SECURITY-NOTES.md`. Git-history metadata and a deleted historical share URL have separate caveats documented there.

## Day-4 live verification

See `DAY4-E2E-REPORT.md` for the 2026-09-27 live server-PC verification and final follow-up disposition. The resource-pack SHA1 item was accepted by the user without successful technical SHA verification.


## Day-5 integration stability

See `DAY5-STABILITY-REPORT.md`. Day 5 is closed from user-confirmed operational use; no fresh diagnostic replay was collected for that closure. Day 6 Android/iOS device verification is in progress.
