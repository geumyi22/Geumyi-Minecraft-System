# GSCM 1.5.1+151

**2026-10-11 최신 수동 설치 Stable 공개.** [GSCM 1.5.1+151 Android APK / iOS unsigned IPA](https://github.com/geumyi22/Geumyi-Minecraft-System/releases/tag/system-2026.10.11-stable-gsc451-gscm151)를 게시했습니다. Flutter 분석·단위 테스트, Android 영구 릴리즈 서명, iOS 미서명 빌드가 CI에서 통과했습니다. 설정에 앱 시작 시 최신 버전 자동 *확인*(설정에서 변경 가능) 및 수동 확인을 추가했으며 자동 설치 기능은 아닙니다. 실제 기기 설치·호환성 검증은 별도입니다.

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


## 1.5.1+151 앱 업데이트 확인

- 설정의 '앱 실행 시 새 버전 자동 확인'을 끄거나 켤 수 있으며, '지금 업데이트 확인'으로 수동 조회 가능합니다.
- Android는 GitHub 릴리즈를 열어 사용자가 직접 설치 승인해야 합니다. iOS unsigned IPA는 Apple 코드 서명·프로비저닝 없이는 설치하지 않습니다.
- GSCM 자체 버전 확인은 GSC Host/Client의 서명된 자동 배포 manifest와 별도입니다.
- [실기기 체크리스트](../docs/operations/RELEASE-4.5.1-1.5.1-SMOKE-CHECKLIST.md)
