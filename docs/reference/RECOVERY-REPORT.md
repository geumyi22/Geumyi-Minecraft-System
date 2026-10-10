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
| GeumyiStatusAgent | 0.5.4 | GSC/StatusAgent | Full 9-file Java source reconstruction recovered; clean JDK 21 build validated; historical JAR overlay assembly documented |
| GSCM | 1.1.2+113 | GSCM | Recovered Flutter/Android source and iOS generation scripts; Day-6 realtime-status hotfix and Android/iOS real-device verification completed |
| GST | 1.1.1 HOTFIX | Plugins/GeumyiServerTools | Exact HOTFIX/overlay delta recovered; 31/31 uncompressed JAR entries matched final deployed HOTFIX; legacy 0.1.5 core remains binary-only |
| GDS | 1.1.1 | Plugins/GeumyiDiscordStatus | Recovered full plugin source, stubs and tests |
| GeumyiTechnology | 0.1.3 | Plugins/GeumyiTechnology | Reconstructed source verified against deployed 0.1.3 bytecode/resources; not claimed as untouched original source |
| GeumyiChemistry | 0.4.1 | Plugins/GeumyiChemistry | Reconstructed source verified against deployed 0.4.1 bytecode/resources; not claimed as untouched original source |
| Wild server | Paper 26.3 | Servers/Wild | 2026-09-27 live server-PC evidence captured; sanitized current server.properties tracked; Day-4 Java/GSC/GST/GDS path verified |
| Playground server | Paper 26.3 | Servers/Playground | 2026-09-27 live server-PC evidence captured; sanitized current server.properties tracked; Day-4 Java/GSC/GST/GDS path verified; AutoSaveWorld follow-up later reported resolved |
| Resource packs | Java 26.3 / bundled Bedrock | ResourcePacks | Recovered expanded assets and Wild Geyser mapping |

## Exclusions and limitations

GST's legacy 0.1.5 core remains binary-only, but the 1.1.1 HOTFIX overlay/delta has been recovered exactly. StatusAgent helper sources were reconstructed and validated while retaining the deployed overlay JAR as the runtime baseline. Technology 0.1.3 and Chemistry 0.4.1 are explicitly labeled reconstructions rather than untouched original source archives. The older local/web RCON server manager was not substituted for the current GSC deployment.

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

Tracked-file count changed during Day-3 recovery; SOURCE-MANIFEST.json is synchronized at the end of the Day-3 work.

## 2026-09-27 follow-up

- Added `.github/workflows/system-ci.yml`. System CI run 36299122264 completed successfully: GSC `go test ./...` on Windows, GDS JDK 21 build plus JAR integrity/stub checks, and ResourcePack JSON/`pack.mcmeta`/`manifest.json` validation all passed.
- The first ResourcePack CI attempt exposed a validator assumption: the current Java 26.3 packs use `min_format`/`max_format` ranges rather than legacy `pack_format`. The validator was corrected to accept and validate both forms before the successful rerun.
- Library recovery recheck found `GeumyiServerTools-1.1.1-Source.zip`. A clean rebuild matches the pre-HOTFIX 1.1.1 JAR entry contents. The current Release HOTFIX JAR SHA-256 `af0509ea77f49fab6bf4dea48ddc0d030e50fa0880eb9250185b47e5ec696ac7` differs from that build in exactly three archive entries: `META-INF/geumyi-26.3-upgrade.properties`, `GscRuntimeBridge.class`, and `HealthService.class`. Therefore the exact final HOTFIX source remains unrecovered and the earlier source was not promoted as current.
- The same Library recheck did not expose exact complete source packages for GeumyiTechnology 0.1.3, GeumyiChemistry 0.4.1, or GeumyiStatusAgent 0.5.4. Older source/bundles remain available but were not substituted for the current versions.

## Day 3 — 2026-09-27

- GST 1.1.1 HOTFIX: the user-supplied final HOTFIX JAR SHA-256 matched the existing Release asset (`af0509ea77f49fab6bf4dea48ddc0d030e50fa0880eb9250185b47e5ec696ac7`). The recovered overlay rebuild matched **31/31 uncompressed JAR-entry SHA-256 values**. The exact source delta is documented under `Plugins/GeumyiServerTools`; the older 0.1.5 core is still binary-only.
- GeumyiStatusAgent 0.5.4: all nine Java sources are present. The clean JDK 21 build succeeds. Because the historical deployed artifact reused older precompiled helper classes, a byte-identical clean rebuild is not claimed; normalized bytecode comparison and the historical assembly distinction are documented in `GSC/StatusAgent/RECOVERY.md`.
- GeumyiTechnology 0.1.3: reconstructed from preserved 0.1.0 source, compatibility artifacts and the deployed 0.1.3 JAR. Method/field descriptors and bytecode operations align after compiler-specific normalization; key resources match byte-for-byte.
- GeumyiChemistry 0.4.1: reconstructed from preserved 0.4.0 source and deployed 0.4.1 JAR. The 26.3 compatibility/version delta and resources were verified.
- Wild/Playground: sanitized 2026-09-10 `server.properties` evidence was recovered. RCON/management secrets and historical resource-pack share URLs are not published. These files are evidence only, not replacements for the exact 2026-09-26 live configs.
- Both preserved configs already have `accepts-transfers=true`, relevant to the planned final-day Lobby -> Wild/Playground/Other server-transfer design.
- Public-repository review: current recovered material and the master release were checked for common secret/personal-information patterns. No active credential was identified in the reviewed current material. Git history separately exposes non-noreply commit-email metadata and an old deleted Dropbox share URL; see `SECURITY-NOTES.md`.
- System CI was extended to compile/verify StatusAgent alongside GSC, GDS and ResourcePack checks. Run `36304228157` completed successfully at commit `69b3213ccb9dd4962374678d9069f9a6635a47fa`.
- Public Git-history audit covered all 66 commits for common high-risk patterns. No GitHub/Discord token, private-key header, bearer credential, Korean phone-number or resident-registration-number pattern was found in the reviewed diffs. One Windows user-profile example path in the GSC dashboard was sanitized on current `main` to `C:\\Minecraft\\Server`; the old value remains in historical Git objects unless history is intentionally rewritten.
- Historical diffs still contain the deleted Dropbox release-source URL, and most existing commits expose a non-noreply author email in Git metadata. Those historical records are documented in `SECURITY-NOTES.md`; no destructive history rewrite was performed automatically.
- After sanitizing the public GSC dashboard example path, System CI run `36305340513` completed successfully. All four jobs passed: GSC Go tests, StatusAgent JDK 21 build, GDS JDK 21 build, and ResourcePack metadata validation.
- Source preservation follow-up: the recovered GST 1.1.1 HOTFIX overlay source, GeumyiTechnology 0.1.3 reconstructed source, and GeumyiChemistry 0.4.1 reconstructed source are now tracked under `Plugins/` on `main`; this closes the prior gap where only recovery documentation was tracked.
- The newly tracked source snapshots were screened before publication for GitHub/Discord token forms, private-key headers, Dropbox share URLs, Windows user-profile paths, and email-address patterns; no matches were found.
- Day-3 recovery work is closed with one deliberate runtime boundary: the exact 2026-09-26 Wild/Playground live configuration cannot be proven from preserved archives and must be captured from the actual server PC during E2E work.

## Day 4 — 2026-09-27

- Live Wild and Playground evidence was collected from the actual server PC. Both servers reached the Paper 26.3 running state with 24 plugin JARs detected on each server.
- Host Java 25.0.4.1 LTS was captured.
- GSC 4.2.3 showed Wild and Playground online. GSCM 1.1.2 showed a realtime Control API connection, Agent online and two managed Minecraft servers online.
- Discord status output identified StatusAgent 0.5.4, Wild/Playground online, GST `HEALTHY`, approximately 20 TPS and fresh heartbeats. Offline detection followed by recovery notification was also observed.
- Runtime JAR hashes matched GitHub Release assets for GST/GDS on both servers and for GeumyiTechnology 0.1.3 / GeumyiChemistry 0.4.1 on Wild.
- Current sanitized live `server.properties` snapshots are tracked as `Servers/Wild/server.properties.e2e-2026-09-27` and `Servers/Playground/server.properties.e2e-2026-09-27`. Both retain `accepts-transfers=true`.
- User-approved exclusions: Bedrock/Geyser offline/enable failure and the transient GSC startup `주의` state are not treated as Day-4 failures.
- Day-4 follow-ups were later closed: the user reported Bedrock/Geyser, AutoSaveWorld and ProtocolLib issues resolved; a V2 repair log showed DiscordSRV added 92 missing top-level keys; resource-pack SHA1 was accepted by the user as non-blocking/pass without a successful technical SHA verification.
- Raw screenshots/log bundles were not committed because they include local paths/network information and a live share URL. Public evidence is sanitized; see `DAY4-E2E-REPORT.md` and `SECURITY-NOTES.md`.
- Day 4 is closed as **completed**. The resource-pack SHA1 item is explicitly recorded as user-accepted rather than technically verified.


## Day 5 — 2026-09-28

- GSC/GSCM integration stability was closed by user-confirmed operational verification.
- The user confirmed working server start/stop/restart/force-stop behavior for Wild and Playground.
- Duplicate-command/lock handling, GSC reconnection, StatusAgent recovery, temporary network recovery, Whole Shutdown and absence of a known remaining orphan-process issue were reported working.
- The Other server control/status/notification path was also reported working.
- No fresh Day-5 diagnostic bundle or replay log was collected, so this is not represented as a newly reproduced assistant-side E2E run.
- No Day-5 source change was required.
- Day 6 begins focused Android/iOS GSCM device verification.


## Day 6 — 2026-09-28

- GSCM Android and iOS real-device verification was completed from user-observed device behavior.
- Android passed pairing persistence, force-close/reopen, device reboot persistence, HTTP snapshot loading, realtime WebSocket state, temporary network-loss recovery, background/foreground refresh, server start/stop/restart, logout and token revocation/re-pairing.
- During Android network-loss testing, the app correctly showed its network-error UI but the header could remain `REALTIME` because the WebSocket had not yet reported TCP teardown.
- GSCM 1.1.2+113 fixed that status-accuracy issue by allowing confirmed HTTP/WS transport failures to override the short WebSocket grace indicator while preserving the anti-flicker grace for brief unconfirmed handoffs.
- Build-113 Android Actions run 36441811005 passed analyze, tests, release APK build and artifact upload. iOS Actions run 36441810896 passed release no-codesign build, unsigned IPA packaging and artifact upload.
- The user then confirmed the corrected Android offline/recovery indicator behavior on-device.
- iOS user verification passed pairing/claim, force-close/reopen persistence, stable device identity, Keychain token reuse, HTTP snapshot, realtime WebSocket, temporary network-loss recovery, background/foreground refresh, server controls, iPhone restart persistence, QR/camera permission flow, local/private-network access, logout and token revocation.
- These results are user-observed physical-device evidence, not assistant-side physical-device execution.
- Stable Android CI/release signing remains a Day-8 packaging task; it is not treated as a Day-6 runtime failure.
- Day 6 is closed as **completed**.


## Day 7 — 2026-09-28

- Expanded System CI to cover GSC, StatusAgent, GST, GDS, GeumyiTechnology, GeumyiChemistry and ResourcePacks.
- GST/GDS build scripts now compile and execute their CoreTests before packaging.
- GST CI verifies the pinned deployed HOTFIX reference/core SHA-256 before overlay compilation; this preserves the documented legacy binary-only boundary rather than claiming full source recovery.
- Technology/Chemistry initially exposed an incompatible recovered Gradle setting: Paper 26.3 requires JVM 25 dependency compatibility while the builds forced release 21. The build target was aligned with Java 25 and both jobs then passed on Gradle 9.1.0.
- GSC Setup CI now downloads the fresh Agent/GDS/GST artifacts from the same workflow run and successfully assembles Host, Client and Setup binaries.
- Final System CI run 36448831023 passed all component jobs and the aggregate Day-7 summary.
- GSCM workflows were pinned to Flutter 3.47.5, now read 1.1.2+113 from pubspec for artifact naming, and generate directly verifiable checksum sidecars.
- Android run 36448477722 passed analyze, tests and APK creation.
- Final iOS run 36449571301 passed analyze, tests, no-codesign build and uploaded only the final IPA plus checksum (temporary Payload packaging files excluded).
- Downloaded Day-7 artifacts were inspected for archive integrity and checksum consistency. Technology/Chemistry output class major is 69 (Java 25); GST/GDS/StatusAgent output class major is 65 (Java 21).
- Day 7 is build/CI verification only. None of these CI artifacts are claimed to have been automatically deployed or newly E2E-tested on the live Minecraft servers.
- Android persistent release signing, deployment manifests/channels and the server pre-start updater remain Day-8 work.
