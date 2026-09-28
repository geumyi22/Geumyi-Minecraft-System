# GSCM 1.1.2+113

Recovered Flutter application source, Android platform code, Kotlin secure storage, tests, Windows Android builders and iOS preparation scripts.

Source of truth: this directory. Both root GitHub Actions workflows now copy GSCM into their existing app build directory. The previous base64 archive was decoded and removed to avoid two competing source copies.

The source is based on the recovered CLEAN 1.1.2 baseline; build 113 adds the Day-6 realtime status-accuracy hotfix. Android Gradle settings preserve the successful existing Actions compatibility configuration. A private-looking address in the QR test fixture was replaced with an example CGNAT address; pairing code 12345678 is synthetic test data.

See [BUILD.md](BUILD.md). Version comes from pubspec.yaml (1.1.2+113). No real tokens, keystores or Apple signing credentials are included.
