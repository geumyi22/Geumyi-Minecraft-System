# Build GSCM 1.1.2+112

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
