# Day 8 — Secure Release / Auto-Update Report

기준일: 2026-09-29

## 상태

**GitHub 구현/CI: 완료**  
**서버 PC 실제 signed-canary E2E: PASS**  
**Day 8 전체 종결: 완료**

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
- Windows finalizer/signing preflight System CI run `36574083087`: PASS
- installer-resume hotfix System CI run `36576774848`: PASS
- Day-8 Secure Release run `36574955584`: PASS
- published canary tag: `system-2026.09.29-222513-canary`
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
  - Windows PowerShell 5.1 compatibility
  - gh / keytool / OpenSSL discovery
  - ASCII/no-BOM CMD launcher parser check

## 서버 PC 실제 E2E 결과

2026-09-29 서버 PC에서 Day-8 finalizer를 실행했습니다.

- 최초 실행 중 Windows CMD UTF-8 BOM 문제를 재현하고 ASCII/no-BOM launcher로 수정
- GitHub CLI interactive login 성공 후 batch `errorlevel` 오판 문제 수정
- 서버 PC의 `keytool.exe` 탐색 실패를 재현하고 JDK 자동 탐색 + Windows preflight CI 추가
- GSC Setup 종료 후 `Start-Process -Wait` descendant wait hang을 재현하고 Setup PID만 기다리도록 수정
- 이미 성공한 signed canary Release를 `-ReuseExistingRelease`로 재사용하여 중복 Release 빌드 없이 E2E 재개
- 사용자 화면 확인 기준 최종 결과: `DAY 8 RESUME FINALIZER: PASS`

최종 PASS가 의미하는 finalizer 내부 조건:
1. signed manifest 검증 PASS
2. 모든 Release artifact SHA-256 / size 검증 PASS
3. GSC Day-8 Update API PASS
4. Wild update check 수행
5. 접속자 0명 상태에서 Wild lifecycle 수행
6. Wild에 enabled GeumyiTechnology가 정확히 1개이며 버전 0.1.4
7. Playground에 GeumyiTechnology 없음
8. updater phase가 `applied` 또는 `current`

서버 PC 로그/result 파일 자체는 이 보고서에 커밋하지 않았으므로, 이 항목은 **finalizer PASS 화면에 대한 사용자 확인**과 GitHub Release/CI 기록을 함께 근거로 합니다. 독립적으로 새 서버 PC를 재현한 assistant-side E2E라고 기록하지 않습니다.

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
