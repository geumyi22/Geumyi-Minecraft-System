# Day 6 GSCM Android+iOS device verification — 2026-09-28

Status: **IN PROGRESS**

## Baseline

- GSC: 4.2.3
- GSCM: 1.1.2+112
- StatusAgent: 0.5.4
- Day 5 control/reconnection behavior: user operational verification complete

## Preflight static audit

- GSCM application/platform source is unchanged from commit `6424982e9c290d439a35207112dd7fd4a868ee36`, where both Android and unsigned iOS GitHub Actions builds succeeded.
- The latest successful System CI remains applicable to its covered GSC/StatusAgent/GDS/ResourcePack source because those covered source paths have not changed since that run.
- GST, GeumyiTechnology and GeumyiChemistry are not currently covered by System CI; expanding automated build coverage is intentionally scheduled for Day 7 and is not a Day-6 device-test blocker.
- Two harmless version-identification strings remain in recovered runtime source: the GSCM HTTP User-Agent says `GSCM/1.0.0 Android`, and the Agent Discord REST User-Agent says `GeumyiStatusAgent/0.5.3`. They do not affect protocol behavior. They are deliberately left unchanged before Day 6 so Git source continues to correspond to the already-built/runtime baseline; centralizing version metadata belongs to Day 7/8.
- Coordinated-baseline documentation and installer-template comments were normalized to GST 1.1.1 HOTFIX, GDS 1.1.1 and Agent 0.5.4 before device testing.

## Evidence rule

Day 6 requires actual device behavior. GitHub Actions build success alone does not count as device verification.

Record Android and iOS separately. A result may be marked PASS from user-observed real-device behavior; do not represent it as assistant-side device execution.

## Android

- [ ] Existing paired connection opens without re-pairing after app force-close/reopen
- [ ] Device ID remains the same after reopen
- [ ] Stored token remains usable after reopen
- [ ] Dashboard snapshot loads by HTTP
- [ ] WebSocket reaches realtime/ONLINE state
- [ ] Temporary network loss recovers without re-pairing
- [ ] App background -> foreground refreshes state
- [ ] Server start/stop/restart action from GSCM works
- [ ] App/device restart preserves connection
- [ ] Local logout clears only local saved connection as designed
- [ ] Revoking the current device token forces re-pairing as designed

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
