# Build GSCM 1.1.5+117

## GitHub Actions

Android and iOS workflows build directly from `GSCM/` with Flutter **3.47.5 stable**.

Artifact names are derived from `pubspec.yaml`:
- Android: `GSCM-1.1.5-build116-Android`
- iOS: `GSCM-1.1.5-build116-iOS-unsigned`

Files inside the artifacts retain the full Flutter build identifier:
- `GSCM-v1.1.5+117-Android.apk`
- `GSCM-v1.1.5+117-unsigned.ipa`

Analyze and tests run before release builds. Secure system releases invoke Android with the persistent release signer; ordinary push CI artifacts are build/test artifacts and must not be substituted for the persistently signed in-place-update APK.

## Android on Windows

Run `GSCM_Build_APK.cmd`. `GSCM_Build_APK_Fast.cmd` skips analyze/tests and is for local iteration only.

The one-click builder reads the version from `pubspec.yaml` and writes a versioned APK under `dist/`.

## iOS on macOS

With Flutter 3.47.5 and Xcode installed:

```bash
chmod +x tool/ios/patch_ios.sh
./tool/ios/patch_ios.sh
flutter pub get
flutter analyze
flutter test
flutter build ios --release --no-codesign
```

Unsigned IPA generation is a compile/package verification path. Installation on an iPhone still requires valid Apple signing/provisioning.
