# GSCM 1.1.5+117

Geumyi Server Center Mobile Flutter source for Android and iOS.

Source of truth: this directory. The app version comes only from `pubspec.yaml`; UI version text reads platform package metadata instead of hard-coded strings.

Current Day 11 status:
- Build 117 adds Protection & Recovery 2.0 backup provenance, restore preflight and destructive-action safeguards.
- Android: `1.1.5+117` is the current source/CI candidate; persistent-signed release and user-device update verification are still pending.
- iOS: `1.1.5+117` is the current unsigned-IPA source/CI candidate; installation still follows Apple signing/provisioning constraints.
- Shared Control API / WebSocket / secure-storage behavior remains covered by CI tests.

Historical recovery baseline was GSCM 1.1.2. Current runtime development continues from that recovered source; historical reports keep their original version labels.

See [BUILD.md](BUILD.md). No real tokens, keystores, RCON passwords, or Apple signing credentials belong in this repository.
