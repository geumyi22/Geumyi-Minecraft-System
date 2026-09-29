# Version and source recovery matrix

Confirmed runtime baseline: 2026-09-26. Recovery/verification status updated 2026-09-29.

CI:
- System CI run 36299122264: GSC, GDS and ResourcePack validation passed.
- System CI run 36304228157: follow-up run with StatusAgent JDK 21 source build completed successfully alongside GSC, GDS and ResourcePack validation.
- System CI run 36305340513: post-security-sanitization verification completed successfully; GSC, StatusAgent, GDS and ResourcePack jobs all passed.
- Pre-Day-6 System CI run 36344295861: GSC, StatusAgent, GDS and ResourcePack jobs all passed on the normalized preflight commit.
- Pre-Day-6 GSCM Android run 36344295867: analyze, tests, release APK build and artifact upload passed.
- Pre-Day-6 GSCM iOS run 36344295880: release no-codesign build, unsigned IPA packaging and artifact upload passed.
- Day-6 GSCM build 113 Android run 36441811005: analyze, tests, release APK build and artifact upload passed.
- Day-6 GSCM build 113 iOS run 36441810896: release no-codesign build, unsigned IPA packaging and artifact upload passed.
- Day-7 System CI run 36448831023: GSC, Agent, GST, GDS, Technology, Chemistry, ResourcePacks, GSC Setup assembly and aggregate summary all passed.
- Day-7 GSCM Android run 36448477722: Flutter 3.47.5, analyze, tests, release APK and clean checksum artifact passed.
- Day-7 final GSCM iOS run 36449571301: Flutter 3.47.5, analyze, tests, unsigned IPA build and clean IPA+checksum artifact passed.
- Day-8 foundation PR CI: secure release/updater, Android release build, iOS unsigned build and GSC setup all passed before merge.
- Day-8 E2E-finalizer PR System CI run 36547936752: Technology 0.1.4, GSC tests/setup, release foundation static tests and PowerShell parser all passed.
- Day-8 post-merge main System CI run 36548257976: all component jobs and aggregate summary passed.

| Component | Baseline | Path | Recovery status |
|---|---|---|---|
| GSC | 4.2.3 | GSC/ServerCenter | Recovered source; Windows Go tests pass; Day-7 CI also assembles Setup from freshly built Agent/GDS/GST artifacts |
| GeumyiStatusAgent | 0.5.4 | GSC/StatusAgent | Full 9-file Java source reconstruction present; Day-7 JDK 21 clean build/artifact succeeds; byte-identical historical rebuild is not claimed |
| GSCM | 1.1.2+113 | GSCM | Day-6 device verification complete; Day-8 persistent Android release-signing path and signed Release workflow implemented/CI-verified; local signer transition/install E2E remains pending |
| GST | 1.1.1 HOTFIX | Plugins/GeumyiServerTools | HOTFIX overlay source tracked; Day-7 JDK 21 overlay build + CoreTests + artifact passes; legacy core remains binary-only and uses a pinned verified reference in CI |
| GDS | 1.1.1 | Plugins/GeumyiDiscordStatus | Recovered full source/stubs/tests; Day-7 JDK 21 build + CoreTests + artifact passes |
| GeumyiTechnology | 0.1.4 | Plugins/GeumyiTechnology | Gameplay logic remains reconstructed/verified 0.1.3 baseline; Day-8 metadata-only bump to 0.1.4 provides a real Wild-only updater E2E marker; JDK 25 / Gradle 9.1.0 CI passes |
| GeumyiChemistry | 0.4.1 | Plugins/GeumyiChemistry | Reconstructed source tracked; Day-7 JDK 25 / Gradle 9.1.0 build produces Paper 26.3 artifact (class major 69); original-source claim unchanged |
| Wild server | Paper 26.3 | Servers/Wild | 2026-09-27 live E2E evidence captured; sanitized current server.properties tracked; GSC/GST/GDS runtime healthy; Day-4 milestone closed |
| Playground server | Paper 26.3 | Servers/Playground | 2026-09-27 live E2E evidence captured; sanitized current server.properties tracked; GSC/GST/GDS runtime healthy; Day-4 milestone closed |
| Resource packs | Java 26.3 / bundled Bedrock | ResourcePacks | Recovered expanded assets and Wild Geyser mapping; JSON/metadata CI passes |

## Public repository note

The repository is now public. Current tracked/recovered material was reviewed for common credential and personal-information patterns; see `SECURITY-NOTES.md`. Git-history metadata and a deleted historical share URL have separate caveats documented there.

## Day-4 live verification

See `DAY4-E2E-REPORT.md` for the 2026-09-27 live server-PC verification and final follow-up disposition. The resource-pack SHA1 item was accepted by the user without successful technical SHA verification.


## Day-5 integration stability

See `DAY5-STABILITY-REPORT.md`. Day 5 is closed from user-confirmed operational use; no fresh diagnostic replay was collected for that closure. Day 6 Android/iOS user real-device verification is complete; see `DAY6-DEVICE-TEST.md`.


## Day-7 automatic build foundation

See `DAY7-CI-REPORT.md`. Final System CI run 36448831023 and mobile runs 36448477722 / 36449571301 passed. Day 7 validates automatic builds and artifacts only; production auto-deployment starts in Day 8.


## Day-8 secure release / updater

See `DAY8-RELEASE-REPORT.md` and `DAY8-RUNBOOK.md`. GitHub-side implementation and CI are complete. Server-PC signed-canary / real pre-start replacement E2E remains the closure gate.
