# GSCM 1.5.0+150

**2026-10-11 수동 설치 Stable 공개.** [GSCM 1.5.0+150 Android APK/iOS unsigned IPA](https://github.com/geumyi22/Geumyi-Minecraft-System/releases/tag/system-2026.10.11-stable-gsc450-gscm150)가 GitHub Latest에 등록됐습니다. 기존 1.1.5+117 기반 버전 정리판으로 신규 기능을 주장하지 않습니다. Flutter 분석·테스트·Android 서명 릴리즈 빌드·iOS 미서명 빌드가 CI에서 통과했으며, 실제 새 버전 설치는 별도입니다.

Geumyi Server Center Mobile Flutter source for Android and iOS.

Source of truth: this directory. The app version comes only from `pubspec.yaml`; UI version text reads platform package metadata instead of hard-coded strings.

Day 11 final status (historical live-verified baseline):
- Build 117 adds Protection & Recovery 2.0 backup provenance, restore preflight and destructive-action safeguards.
- `1.1.5+117` is the final Day-11 GSCM baseline.
- Android/iOS artifacts remain subject to their normal signing/distribution constraints.
- The final two requested GSCM Day-11 device checks were user-confirmed PASS.
- Shared Control API / WebSocket / secure-storage behavior remains covered by CI tests.
- Day 11은 완료됐고 Day 12도 소규모 운영 수락 기준으로 마감됐습니다. 정식 보안 게이트는 계속 차단합니다.

Historical recovery baseline was GSCM 1.1.2. Current runtime development continues from that recovered source; historical reports keep their original version labels.

See [BUILD.md](BUILD.md). No real tokens, keystores, RCON passwords, or Apple signing credentials belong in this repository.
