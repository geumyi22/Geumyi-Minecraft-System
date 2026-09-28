# Day 6 GSCM Android+iOS device verification — 2026-09-28

Status: **IN PROGRESS**

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
- [ ] App background -> foreground refreshes state
- [ ] Server start/stop/restart action from GSCM works
- [x] App/device restart preserves connection — user rebooted the Android device and GSCM reopened without re-pairing
- [ ] Local logout clears only local saved connection as designed
- [ ] Revoking the current device token forces re-pairing as designed

### Android evidence — force-close/reopen

User performed a real Android force-stop and reopened GSCM. The app returned directly to Command Center without requesting a new pairing code. The resulting screen showed GSC 4.2.3 / Control API v1, REALTIME, Agent ONLINE, and the current 2/3 server-online state. This is recorded as user-observed real-device evidence, not assistant-side device execution.

### Android observation — offline badge accuracy

Network-loss recovery itself passed: with both Wi-Fi and mobile data disabled, GSCM showed its designed network error UI and recovered after connectivity returned without re-pairing.

However, the top realtime badge remained `REALTIME` while the app was already reporting a network error. Source review explains the mismatch: the badge is driven by `realtimeUiHealthy`, which remains true while the existing WebSocket has not yet emitted onDone/onError (or during its disconnect grace interval). Mobile OS TCP teardown can lag behind HTTP failure detection.

Disposition: **Patch implemented in GSCM 1.1.2+113; runtime re-test pending.** Confirmed transport failures now override the WebSocket grace indicator, while unconfirmed short handoffs retain the 5-second anti-flicker grace. The original recovery behavior remains PASS; offline badge accuracy will be marked PASS only after the updated APK is tested on-device.

### Android evidence — device reboot persistence

User rebooted the Android device and confirmed GSCM still opened directly into the connected state without a new pairing flow. This verifies persistence across a full device reboot at the user-observed runtime level.

## iOS

- [ ] Pairing/claim succeeds on a real iPhone
- [ ] Existing paired connection opens without re-pairing after app force-close/reopen
- [ ] Device ID remains the same after reopen
- [ ] Keychain token remains usable after reopen
- [ ] Dashboard snapshot loads by HTTP
- [ ] WebSocket reaches realtime/ONLINE state
- [ ] Temporary network loss recovers without re-pairing
- [ ] App background -> foreground refreshes state
- [ ] Server start/stop/restart action from GSCM works
- [ ] iPhone restart preserves connection
- [ ] Camera permission / QR pairing path works
- [ ] Local-network access path works on LAN/private VPN
- [ ] Local logout and token revocation behave as designed

## Implementation expectations

- Android stores the device token using AndroidKeyStore AES-256-GCM and keeps host/device metadata in private SharedPreferences.
- iOS stores the device token in Apple Keychain with ThisDeviceOnly accessibility and keeps host/device metadata in UserDefaults.
- GSCM loads a stored connection on app startup.
- Dashboard state has a 30-second HTTP reconciliation poll while foregrounded.
- WebSocket reconnect uses progressive delays after loss and a short disconnect grace period to avoid transient UI churn.

## Completion rule

Day 6 closes only after Android and iOS real-device behavior is recorded, or after an explicit documented scope decision if one platform cannot be tested.
