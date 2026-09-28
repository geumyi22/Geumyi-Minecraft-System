# Day 6 GSCM Android+iOS device verification — 2026-09-28

Status: **COMPLETED**

## Baseline

- GSC: 4.2.3
- GSCM: 1.1.2+112 was the initial device-test build; Day-6 status hotfix target is 1.1.2+113
- StatusAgent: 0.5.4
- Day 5 control/reconnection behavior: user operational verification complete

## Preflight static audit

- GSCM application/platform source is unchanged from commit `6424982e9c290d439a35207112dd7fd4a868ee36`, where both Android and unsigned iOS GitHub Actions builds succeeded.
- The latest successful System CI remains applicable to its covered GSC/StatusAgent/GDS/ResourcePack source because those covered source paths have not changed since that run.
- GST, GeumyiTechnology and GeumyiChemistry are not currently covered by System CI; expanding automated build coverage is intentionally scheduled for Day 7 and is not a Day-6 device-test blocker.
- Two harmless version-identification strings remain in recovered runtime source: the GSCM HTTP User-Agent says `GSCM/1.0.0 Android`, and the Agent Discord REST User-Agent says `GeumyiStatusAgent/0.5.3`. They do not affect protocol behavior. They are deliberately left unchanged before Day 6 so Git source continues to correspond to the already-built/runtime baseline; centralizing version metadata belongs to Day 7/8.
- Coordinated-baseline documentation and installer-template comments were normalized to GST 1.1.1 HOTFIX, GDS 1.1.1 and Agent 0.5.4 before device testing.
- Fresh pre-Day-6 CI on commit `9c0da6cd1b3400c92c804ab8c4e93a6a3b5bd390` passed:
  - System CI run [36344295861](https://github.com/geumyi22/Geumyi-Minecraft-System/actions/runs/36344295861): GSC Go tests, StatusAgent JDK 21 build, GDS JDK 21 build and ResourcePack validation all passed.
  - Android run [36344295867](https://github.com/geumyi22/Geumyi-Minecraft-System/actions/runs/36344295867): Flutter package resolution, analyze, tests, release APK build and artifact upload passed.
  - iOS run [36344295880](https://github.com/geumyi22/Geumyi-Minecraft-System/actions/runs/36344295880): iOS Runner preparation, release no-codesign build, unsigned IPA packaging and artifact upload passed.
- The commits after that CI only update documentation and `SOURCE-MANIFEST.json`; application/runtime source is unchanged.

## Evidence rule

Day 6 requires actual device behavior. GitHub Actions build success alone does not count as device verification.

Record Android and iOS separately. A result may be marked PASS from user-observed real-device behavior; do not represent it as assistant-side device execution.

## Android

- [x] Existing paired connection opens without re-pairing after app force-close/reopen — user-observed on Android 2026-09-28
- [x] Device ID remains stable across reopen/reboot — user-observed Android device retained the paired identity
- [x] Stored token remains usable after reopen — authenticated dashboard/realtime connection restored after force-close/reopen
- [x] Dashboard snapshot loads by HTTP — dashboard populated with current GSC/host/server state after reopen
- [x] WebSocket reaches realtime/ONLINE state — screenshot showed REALTIME and Agent ONLINE after reopen
- [x] Temporary network loss recovers without re-pairing — user disabled both Wi-Fi and mobile data, then restored connectivity; GSCM recovered without pairing again
- [x] App background -> foreground refreshes state — user-observed on Android 2026-09-28
- [x] Server start/stop/restart action from GSCM works — user-observed on Android 2026-09-28
- [x] App/device restart preserves connection — user rebooted the Android device and GSCM reopened without re-pairing
- [x] Local logout clears only local saved connection as designed — user-observed on Android 2026-09-28
- [x] Revoking the current device token forces re-pairing as designed — user-observed on Android 2026-09-28

### Android evidence — force-close/reopen

User performed a real Android force-stop and reopened GSCM. The app returned directly to Command Center without requesting a new pairing code. The resulting screen showed GSC 4.2.3 / Control API v1, REALTIME, Agent ONLINE, and the current 2/3 server-online state. This is recorded as user-observed real-device evidence, not assistant-side device execution.

### Android observation — offline badge accuracy

Network-loss recovery itself passed: with both Wi-Fi and mobile data disabled, GSCM showed its designed network error UI and recovered after connectivity returned without re-pairing.

However, the top realtime badge remained `REALTIME` while the app was already reporting a network error. Source review explains the mismatch: the badge is driven by `realtimeUiHealthy`, which remains true while the existing WebSocket has not yet emitted onDone/onError (or during its disconnect grace interval). Mobile OS TCP teardown can lag behind HTTP failure detection.

Disposition: **PASS on GSCM 1.1.2+113 real Android device.** User confirmed that disabling Wi-Fi and mobile data changes the top status away from `REALTIME`, and restoring connectivity automatically returns it to `REALTIME` without re-pairing. The original recovery behavior and the corrected offline-badge accuracy both pass.

Patch verification:
- Source commit: `8a62780c466151bb4bec2c2654ce28a8031ad850`
- Android Actions run [36441811005](https://github.com/geumyi22/Geumyi-Minecraft-System/actions/runs/36441811005): `flutter analyze`, `flutter test`, release APK build and artifact upload all passed.
- iOS Actions run [36441810896](https://github.com/geumyi22/Geumyi-Minecraft-System/actions/runs/36441810896): release no-codesign build, unsigned IPA packaging and artifact upload all passed.
- Android APK SHA-256: `b30d116b15c603bad0654b2683856da4679c042ae8686047fc8afa692e77fb25`
- The new unit tests verify that confirmed network/refused/timeout failures override both an apparently live WebSocket and the short disconnect grace window.

### Android evidence — device reboot persistence

User rebooted the Android device and confirmed GSCM still opened directly into the connected state without a new pairing flow. This verifies persistence across a full device reboot at the user-observed runtime level.

### Android final Day-6 result

**PASS — user-observed real-device verification complete on GSCM 1.1.2+113.**

The user additionally confirmed background/foreground recovery, GSCM server start/stop/restart controls, local logout behavior, and current-device token revocation/re-pairing behavior. Android Day-6 verification is therefore closed. This remains user-observed device evidence rather than assistant-side physical-device execution.

## iOS

- [x] Pairing/claim succeeds on a real iPhone — user-observed on iOS 2026-09-28
- [x] Existing paired connection opens without re-pairing after app force-close/reopen — user-observed on iOS 2026-09-28
- [x] Device ID remains the same after reopen — user-observed on iOS 2026-09-28
- [x] Keychain token remains usable after reopen — user-observed on iOS 2026-09-28
- [x] Dashboard snapshot loads by HTTP — user-observed on iOS 2026-09-28
- [x] WebSocket reaches realtime/ONLINE state — user-observed on iOS 2026-09-28
- [x] Temporary network loss recovers without re-pairing — user-observed on iOS 2026-09-28
- [x] App background -> foreground refreshes state — user-observed on iOS 2026-09-28
- [x] Server start/stop/restart action from GSCM works — user-observed on iOS 2026-09-28
- [x] iPhone restart preserves connection — user-observed on iOS 2026-09-28
- [x] Camera permission / QR pairing path works — user-observed on iOS 2026-09-28
- [x] Local-network access path works on LAN/private VPN — user-observed on iOS 2026-09-28
- [x] Local logout and token revocation behave as designed — user-observed on iOS 2026-09-28

### iOS final Day-6 result

**PASS — user-observed real-device verification complete on GSCM 1.1.2+113.**

The user confirmed that pairing/claim, persistence across force-close and iPhone restart, Keychain-backed token reuse, HTTP snapshot loading, realtime WebSocket recovery, temporary network-loss recovery, background/foreground state refresh, server start/stop/restart controls, QR/camera permission flow, LAN/private-network access, logout, and token revocation all worked on the iPhone.

### Day-6 final result

**COMPLETED — Android and iOS user-observed real-device verification passed.**

Android additionally verified the build-113 realtime badge fix after a reproduced offline-status mismatch was found during Day 6. Stable Android release signing remains a Day-8 packaging task and is not a Day-6 runtime blocker.

## Implementation expectations

- Android stores the device token using AndroidKeyStore AES-256-GCM and keeps host/device metadata in private SharedPreferences.
- iOS stores the device token in Apple Keychain with ThisDeviceOnly accessibility and keeps host/device metadata in UserDefaults.
- GSCM loads a stored connection on app startup.
- Dashboard state has a 30-second HTTP reconciliation poll while foregrounded.
- WebSocket reconnect uses progressive delays after loss and a short disconnect grace period to avoid transient UI churn.

## Android CI signing observation

The Android CI workflow currently uses a runner-generated debug signing key. Direct inspection of the APK Signature Scheme v2 signer certificates found different signer certificate SHA-256 values for the pre-hotfix build 112 and hotfix build 113 artifacts:

- build 112: `7a1147d17008be1a7b3a8b6b8c3ef4e0d0099ba3a562da28e294fc0aa18d3b87`
- build 113: `21ee3524edeee461260589336fcec039967836980d5ad1d7b09ac701286216da`

Therefore a previous CI APK cannot be assumed to support an in-place Android update to build 113. This is a distribution/signing issue, not a realtime-status code failure. Stable signing is deferred to the Day-8 release/packaging work.

## Completion rule

Day 6 is closed: Android and iOS real-device behavior was user-verified. These are user-observed physical-device results, not assistant-side device execution.
