# GSCM iOS platform layer

GSCM 1.1.2 retains the iOS platform layer introduced in 1.1.0: shared Flutter UI/API/WebSocket logic plus iOS-native secure storage.

## Platform channel
Dart continues to call `com.geumyi.gscm/secure_storage` on both platforms.

- Android: `AndroidKeyStore` AES-256-GCM + SharedPreferences
- iOS: Apple Keychain generic-password item + UserDefaults
- iOS token accessibility: `kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly`
- Device ID: generated app-local UUID prefixed with `ios-`
- Device name: `UIDevice.current.name`

## iOS permissions / network
`patch_ios.sh` adds:
- `NSCameraUsageDescription` for GSC pairing QR scanning
- `NSLocalNetworkUsageDescription` for GSC LAN/private-VPN access
- `NSAppTransportSecurity.NSAllowsLocalNetworking = true` for local/IP connections

## Build
On a Mac with Flutter and Xcode:

```bash
chmod +x GSCM_Build_iOS.command tool/ios/patch_ios.sh
./GSCM_Build_iOS.command
```

This performs an unsigned release compile check and opens `ios/Runner.xcworkspace`.
After selecting an Apple Development Team in Xcode, install/run on an iPhone.

For an IPA after signing is configured:

```bash
./GSCM_Build_iOS.command --ipa
```

The first run creates `ios/` from the locally installed Flutter template, then injects GSCM's native platform code. This intentionally avoids shipping a stale Xcode template inside the source archive.
