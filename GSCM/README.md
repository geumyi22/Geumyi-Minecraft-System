# GSCM 1.1.5+117

Geumyi Server Center Mobile Flutter source for Android and iOS.

Source of truth: this directory. The app version comes only from `pubspec.yaml`; UI version text reads platform package metadata instead of hard-coded strings.

Current Day 11 final status:
- Build 117 adds Protection & Recovery 2.0 backup provenance, restore preflight and destructive-action safeguards.
- `1.1.5+117` is the final Day-11 GSCM baseline.
- Android/iOS artifacts remain subject to their normal signing/distribution constraints.
- The final two requested GSCM Day-11 device checks were user-confirmed PASS.
- Shared Control API / WebSocket / secure-storage behavior remains covered by CI tests.
- Day 11 is complete; Day 12 is the next milestone.

Historical recovery baseline was GSCM 1.1.2. Current runtime development continues from that recovered source; historical reports keep their original version labels.

See [BUILD.md](BUILD.md). No real tokens, keystores, RCON passwords, or Apple signing credentials belong in this repository.
