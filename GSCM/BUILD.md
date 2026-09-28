# Build GSCM 1.1.2+113

## GitHub Actions

Android and iOS workflows build directly from `GSCM/` and are pinned to Flutter **3.47.5 stable**, matching the recovered local builder baseline.

Both workflows read the app version from `pubspec.yaml` instead of hard-coding the build number into artifact names.

Current CI artifact naming:
- Android: `GSCM-1.1.2-build113-Android`
- iOS: `GSCM-1.1.2-build113-iOS-unsigned`

The files inside those artifacts retain the full Flutter build identifier:
- `GSCM-v1.1.2+113-Android.apk`
- `GSCM-v1.1.2+113-unsigned.ipa`

Checksum files are generated from inside the artifact directory, so their paths are directly verifiable after extraction.

Android CI runs package resolution, analyze, tests and release APK build. iOS CI runs package resolution, analyze, tests and release no-codesign build.

## Android on Windows

Run `GSCM_Build_APK.cmd` (or `BUILD_ANDROID.cmd`). The recovered tool scripts install/reuse their toolchains and generate the Flutter platform wrapper as needed. `GSCM_Build_APK_Fast.cmd` skips analyze/tests. The output is `dist/GSCM-v1.1.2.apk`.

## Android CI signing caveat

The current GitHub Actions Android workflow still signs the release APK with the runner's generated **debug** signing key. That key is not persisted between Actions runners, so CI artifacts from different runs are not guaranteed to be installable as in-place updates over one another.

Verified during Day 6:
- build 112 signer certificate SHA-256: `7a1147d17008be1a7b3a8b6b8c3ef4e0d0099ba3a562da28e294fc0aa18d3b87`
- build 113 signer certificate SHA-256: `21ee3524edeee461260589336fcec039967836980d5ad1d7b09ac701286216da`

Stable Android release signing is a Day-8 packaging/release requirement. Until then, use the same persistent local signing key for in-place upgrades, or uninstall/re-pair when testing a CI APK.

## iOS on macOS

With Flutter 3.47.5 and Xcode installed, run from this directory:

```bash
chmod +x tool/ios/patch_ios.sh
./tool/ios/patch_ios.sh
flutter pub get
flutter analyze
flutter test
flutter build ios --release --no-codesign
```

Runner is generated from Flutter; the recovered AppDelegate is injected by `patch_ios.sh`. Signing/installing on an iPhone is separate and requires local Apple credentials.
