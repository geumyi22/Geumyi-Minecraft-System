# Changelog

## 1.5.0+150 — 2026-10-11 패키지 Stable
- [Android APK / iOS 미서명 IPA](https://github.com/geumyi22/Geumyi-Minecraft-System/releases/tag/system-2026.10.11-stable-gsc450-gscm150)를 수동 설치용 Stable로 공개. 마지막 실기기 확인 1.1.5+117 기준으로 버전 정리했으며 신규 모바일 기능을 주장하지 않음.
- Flutter analyze/test, Android 영구 릴리즈 서명 빌드, iOS unsigned 패키징 CI 성공. Apple 서명/프로비저닝은 별도 필요.
- 신규 패키지를 기기에 설치하거나 실기기 E2E 검증을 완료했다고 주장하지 않음.

## 1.1.5 — Build 117 — Day-11 final
- Added Protection & Recovery 2.0 mobile controls for backup provenance, restore preflight, protection/Trash state and destructive-action safeguards.
- Coordinated with GSC 4.3.8.
- Android/iOS CI artifacts passed; platform signing/provisioning constraints remain unchanged.
- Final two requested Day-11 GSCM device checks were user-confirmed PASS on 2026-10-07.
- Day 11 closed on GSCM 1.1.5+117.


## 1.1.2

### Build 113 — Day-6 realtime status hotfix
- Confirmed HTTP/WS transport failures now override the short WebSocket disconnect grace window, so the header no longer remains `REALTIME` after the app has already detected that GSC is unreachable.
- Kept the existing 5-second grace behavior for brief Wi-Fi/radio handoffs when no transport failure has been confirmed.
- Added unit tests for transport-failure classification and realtime-indicator precedence.

- Fixed WebSocket reconnect storms caused by overlapping connection attempts and stale socket callbacks.
- Added Android/iOS lifecycle grace handling so short inactive transitions do not tear down realtime.
- Kept 30-second HTTP reconciliation as the fallback consistency path.
- Updated visible app version to 1.1.2.

## 1.1.0
- iOS 플랫폼 지원 추가
- Apple Keychain 기반 device token 보관 구현
- iOS device ID / device name MethodChannel 구현
- iOS QR 카메라 권한 추가
- iOS local network 접근 설명 및 ATS local-network 허용 추가
- Flutter 3.47 UIScene / FlutterImplicitEngineDelegate 방식 MethodChannel 대응
- Android 기존 AndroidKeyStore 저장 방식 유지
- 플랫폼 중립적인 보안 문구/기기 아이콘으로 UI 정리
- Android/iOS bundle/application identifier `com.geumyi.gscm` 유지

## 1.0.0
- 기존 GSCM 1.0 기능 기준선
