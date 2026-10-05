# Version and source recovery matrix

Confirmed runtime baseline: 2026-10-06. Recovery/verification status updated 2026-10-06.

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
- Day-8 Windows finalizer/signing preflight System CI run 36574083087: Windows PowerShell 5.1, gh/keytool/OpenSSL discovery and ASCII/no-BOM CMD launcher checks passed.
- Day-8 installer-resume hotfix System CI run 36576774848: all component jobs and aggregate summary passed.
- Day-8 Secure Release run 36574955584: signed canary Release `system-2026.09.29-222513-canary` published successfully.
- Day-10 recovery-safe exact-main Hotfix CI run 37113499045: Windows PowerShell 5.1 Day10 hotfix/rollback guards passed.
- Day-10 recovery-safe exact-main System CI run 37113499031: full System CI completed successfully for commit `0e1490bfe75975eb278526df0f89a430109e28d8`.

| Component | Baseline | Path | Recovery status |
|---|---|---|---|
| GSC | 4.3.2 | GSC/ServerCenter | Day 11 live self-update 4.3.1→4.3.2 PASS; Host health gate/client relaunch/RCON status verification completed |
| GeumyiStatusAgent | 0.5.4 | GSC/StatusAgent | Full 9-file Java source reconstruction present; Day-7 JDK 21 clean build/artifact succeeds; byte-identical historical rebuild is not claimed |
| GSCM | 1.1.5+116 | GSCM | Day 11 version-display fix; persistent-signed Android release and unsigned iOS IPA published; user device distribution verification completed |
| GST | 1.1.1 HOTFIX | Plugins/GeumyiServerTools | HOTFIX overlay source tracked; Day-7 JDK 21 overlay build + CoreTests + artifact passes; legacy core remains binary-only and uses a pinned verified reference in CI |
| GDS | 1.1.1 | Plugins/GeumyiDiscordStatus | Recovered full source/stubs/tests; Day-7 JDK 21 build + CoreTests + artifact passes |
| GeumyiNetwork | 0.1.0 | Plugins/GeumyiNetwork | Four-server transfer and last-location routing; Java host E2E PASS on 2026-10-03 |
| GeumyiLobby | 0.1.0 | Plugins/GeumyiLobby | Lobby selector/protection/gates; Java host E2E PASS on 2026-10-03 |
| GeumyiTechnology | 0.1.4 | Plugins/GeumyiTechnology | Gameplay logic remains reconstructed/verified 0.1.3 baseline; Day-8 metadata-only 0.1.4 marker was actually deployed/verified on Wild by the server-PC finalizer; Playground remained without Technology; JDK 25 / Gradle 9.1.0 CI passes |
| GeumyiChemistry | 0.4.1 | Plugins/GeumyiChemistry | Reconstructed source tracked; Day-7 JDK 25 / Gradle 9.1.0 build produces Paper 26.3 artifact (class major 69); original-source claim unchanged |
| Wild server | Paper 26.3 | Servers/Wild | 2026-09-27 live E2E evidence captured; sanitized current server.properties tracked; GSC/GST/GDS runtime healthy; Day-4 milestone closed |
| Playground server | Paper 26.3 | Servers/Playground | 2026-09-27 live E2E evidence captured; sanitized current server.properties tracked; Day-10 Java route/location restore verified |
| Other server | Paper 26.3 | Servers/Other | Day-10 backend on private Java 25572; Java route/location restore verified |
| Lobby server | Paper 26.3 | Servers/Lobby | Day-10 backend on private Java 25573; public Java aliases enter Lobby first; reboot E2E verified |
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

See `DAY8-RELEASE-REPORT.md` and `DAY8-RUNBOOK.md`. Day 8 is closed. Secure Release run `36574955584` published `system-2026.09.29-222513-canary`, and the server-PC resume finalizer displayed PASS after verifying the real Wild Technology 0.1.4 pre-start update and Playground isolation. Android ADB signer-transition install remains optional/pending.


## Day-9 transaction / rollback

Day 9 is closed. GSC 4.2.4 transaction backup/staging/commit, interrupted-transaction recovery, post-start health gate, automatic rollback, rejected-release hold, failure injection/self-test, known-good fail-open, and the server-PC Final E2E were completed. Day 8 and Day 9 are both canonical **completed** milestones; their PASS labels are completion evidence, not partial-state labels.

## Day-10 four-server host verification

On 2026-10-03 the user verified the real server PC after cutover and after a Windows reboot. Velocity startup tasks for wild/playground/other were Running; public TCP 25565/25566/25567 were LISTEN; UDP 19132/19133/19134 were BOUND. A real Java client entered Lobby and successfully routed to Wild, Playground and Other, returned with `/lobby`, and restored each backend's previous position.

The original live run recorded Bedrock as `SKIPPED_UPSTREAM_UNSUPPORTED`; that remains historical evidence for the first skipped test. On 2026-10-04 the user later confirmed real Bedrock client operation and approved Day-10 closure. Day 10 is therefore **complete** by user real-client verification. See `DAY10-E2E-REPORT.md`.
