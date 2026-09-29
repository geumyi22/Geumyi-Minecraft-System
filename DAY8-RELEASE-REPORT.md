# Day 8 — Secure Release / Auto-Update Report

기준일: 2026-09-29

## 상태

**GitHub 구현/CI: 완료**  
**서버 PC 실제 signed-canary E2E: 대기**  
**Day 8 전체 종결: 서버 PC E2E PASS 후**

## main 기준 구현

- `.github/workflows/day8-release.yml`
  - Stable / Beta / Canary
  - System / Android / iOS 재빌드
  - checksum sidecar 검증
  - deployment manifest 생성
  - Ed25519 detached signature
  - GitHub Release 게시
- `deploy/components.json`
  - 배포 대상/버전/서버 target 정의
  - Technology 0.1.4 = Wild only
- GSC 4.2.3
  - pre-start updater
  - signed manifest 검증
  - SHA-256/size 검증
  - 기존 Geumyi 자체 플러그인만 대상
  - staging / previous copy safety
  - 업데이트 실패 시 기존 `start.bat` 실행을 막지 않는 fail-open
  - Update Center 1차 UI/API
- Android
  - persistent release keystore를 GitHub Actions Secret으로 공급하는 경로
- 운영 도구
  - `tools/release/bootstrap_day8_signing.ps1`
  - `tools/release/finish_day8.ps1`

## Technology 0.1.4 의미

0.1.4는 Day 8의 실제 pre-start 교체를 증명하기 위한 **metadata-only version bump**입니다.

- gameplay logic: 0.1.3 reconstructed/verified baseline 유지
- plugin version / visible runtime version: 0.1.4
- target: Wild only
- Playground: 배포 대상 아님

## GitHub 검증 근거

- Day-8 E2E-finalizer PR System CI run `36547936752`: PASS
- post-merge main System CI run `36548257976`: PASS
- Technology 0.1.4 Gradle/JDK 25 build: PASS
- GSC Go tests: PASS
- GSC Setup assembly: PASS
- GST / GDS / StatusAgent / Chemistry / ResourcePack validation: PASS
- release foundation static tests:
  - manifest generator
  - Ed25519 sign/verify
  - workflow YAML parse
  - GSC dashboard JavaScript syntax
  - Day-8 PowerShell tool syntax

## Day 8 최종 서버-PC closure gate

관리자 PowerShell에서 repository root 기준:

```powershell
powershell -ExecutionPolicy Bypass -File .\tools\release\finish_day8.ps1 -RunServerE2E
```

검증 항목:

1. persistent Android + deployment signing material 준비/재사용
2. GitHub Actions Secrets 등록
3. Canary Secure Release 실행
4. signed manifest 검증
5. 모든 release artifact SHA-256/size 검증
6. Day-8 GSC Update API 확인
7. Wild dry-check
8. 접속자 0명 확인 후 graceful stop
9. Wild 시작 전 Technology 0.1.4 실제 교체
10. Wild 정상 online
11. Wild inventory에서 Technology 0.1.4 확인
12. Playground에 Technology가 없는지 확인
13. 결과 JSON / E2E log 생성

접속자가 있으면 자동 서버 재시작을 거부합니다.

## Android

선택적 Android ADB 검증:

```powershell
powershell -ExecutionPolicy Bypass -File .\tools\release\finish_day8.ps1 -RunServerE2E -TryAndroidADB
```

Day-6 설치 APK와 새 persistent signer가 다르면 최초 1회 signer transition이 필요할 수 있습니다. finalizer는 앱 데이터 보호를 위해 자동 uninstall하지 않습니다.

## Day 9로 넘기는 항목

- 전체 배포 transaction journal
- release-group 원자성
- post-start health gate
- 자동 rollback
- 장애 주입 / 네트워크 단절 / 손상 artifact E2E

이 항목들은 Day 8 종결 조건에 포함하지 않습니다.
