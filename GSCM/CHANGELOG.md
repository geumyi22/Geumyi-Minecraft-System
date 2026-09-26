# Changelog

## 1.1.2

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
