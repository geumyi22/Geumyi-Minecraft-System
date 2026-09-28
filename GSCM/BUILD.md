# Build GSCM 1.1.2+113

## GitHub Actions

Use the existing Android and iOS workflows at the repository root. They build directly from GSCM/. Android retains its Gradle compatibility setup, analyze/test/build steps and APK artifact naming. iOS prepares the Runner on macOS and produces an unsigned 1.1.2 IPA. Both also support manual workflow_dispatch.

## Android on Windows

Run GSCM_Build_APK.cmd (or BUILD_ANDROID.cmd). The recovered tool scripts install/reuse their toolchains and generate the Flutter platform wrapper as needed. GSCM_Build_APK_Fast.cmd skips analyze/tests. The output is dist/GSCM-v1.1.2.apk. Release builds currently use a generated debug signing key, as in the original workflow. No signing key is committed.

## iOS on macOS

With Flutter and Xcode installed, run from this directory:

```bash
chmod +x tool/ios/patch_ios.sh
./tool/ios/patch_ios.sh
flutter pub get
flutter analyze
flutter test
flutter build ios --release --no-codesign
```

Runner is generated from Flutter; the recovered AppDelegate is injected by patch_ios.sh. Signing/installing on an iPhone is separate and requires local Apple credentials. Legacy launcher files referring to absent scripts were excluded.


## CI APK signing caveat

The current GitHub Actions Android workflow signs the release APK with the runner's generated **debug** signing key. That key is not persisted between Actions runners, so CI artifacts from different runs are not guaranteed to be installable as in-place updates over one another.

Verified during Day 6:
- build 112 signer certificate SHA-256: `7a1147d17008be1a7b3a8b6b8c3ef4e0d0099ba3a562da28e294fc0aa18d3b87`
- build 113 signer certificate SHA-256: `21ee3524edeee461260589336fcec039967836980d5ad1d7b09ac701286216da`

The certificates differ. Stable release signing is therefore a Day-8 packaging/release requirement. Until then, use the same persistent local signing key for in-place upgrades, or uninstall/re-pair when testing a CI APK.
