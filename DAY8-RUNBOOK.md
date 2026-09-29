# Day 8 operator runbook

## 1. Signing bootstrap

관리자 PowerShell에서 repository root 기준:

```powershell
powershell -ExecutionPolicy Bypass -File .\tools\release\bootstrap_day8_signing.ps1
```

이 작업은 다음 GitHub Actions secrets를 등록합니다.

- `ANDROID_RELEASE_KEYSTORE_B64`
- `ANDROID_RELEASE_STORE_PASSWORD`
- `ANDROID_RELEASE_KEY_ALIAS`
- `ANDROID_RELEASE_KEY_PASSWORD`
- `DEPLOYMENT_ED25519_PRIVATE_KEY_B64`

그리고 manifest 검증 public key를 기본 GSC 위치인
`%ProgramData%\GeumyiServerCenter\deployment-public.pem`에 복사합니다.

Private key / Android keystore는 repository에 commit하지 않습니다.

### 기존 Android 앱 업데이트 주의

Day 6에서 확인된 CI APK build 113 signer SHA-256은:

`21ee3524edeee461260589336fcec039967836980d5ad1d7b09ac701286216da`

그 CI runner의 private debug key는 지속 보관되지 않았습니다. 따라서 현재 휴대폰의 GSCM이 그 signer로 설치되어 있고 동일 private key를 별도로 보유하지 않았다면 **Day 8 persistent signer로 전환하는 최초 1회만 앱 삭제/재설치가 필요**합니다. 이후 Day 8 keystore를 계속 보존하면 같은 applicationId + signer로 in-place update가 가능합니다.

기존 private keystore를 실제로 보유하고 있다면 bootstrap script의 `ExistingAndroidKeystore` 계열 매개변수로 전달해 그대로 승계할 수 있습니다.

## 2. Secure Release 실행

GitHub Actions에서 **Day 8 Secure Release**를 수동 실행합니다.

첫 검증은:

- channel: `canary`
- tag: 예: `system-2026.09.29-canary.1`
- prerelease: `true`

Release workflow는 System CI + GSCM Android/iOS를 다시 빌드한 뒤 다음을 수행합니다.

1. artifact checksum 검증
2. deployment manifest 생성
3. Ed25519 detached signature 생성/자체 검증
4. GitHub Release 생성

## 3. GSC updater 활성화

Release가 실제로 성공한 뒤 로컬 GSC API에서:

```powershell
$body = @{
  enabled = $true
  channel = "canary"
} | ConvertTo-Json

Invoke-RestMethod   -Method Post   -Uri "http://127.0.0.1:8787/api/v4/update/settings"   -ContentType "application/json"   -Body $body
```

기본 로컬 설정은 loopback no-auth가 허용된 기존 GSC 설정을 전제로 합니다. 해당 옵션을 껐다면 정상 API token 인증을 사용해야 합니다.

## 4. Dry check

```powershell
Invoke-RestMethod   -Method Post   -Uri "http://127.0.0.1:8787/api/v4/update/check"   -ContentType "application/json"   -Body '{"id":"wild"}'
```

`available` 목록에 실제 설치된 자체 플러그인의 새 버전만 나타나는지 확인합니다.

## 5. Next-start update

서버가 꺼진 상태에서 GSC로 시작합니다.

GSC는:

- GitHub Release 목록에서 선택한 channel의 최신 signed manifest 검색
- 로컬 trusted Ed25519 public key로 manifest 검증
- artifact SHA-256 / size 검증
- **이미 설치된 Geumyi 자체 plugin만** staging 후 교체
- update 오류가 나면 기존 파일을 유지/복원하고 원래 `start.bat` 시작 계속

을 수행합니다.

Day 8은 pre-start update foundation입니다. 전체 트랜잭션 journal, release-group 원자성, post-start health rollback 및 장애 주입 시험은 Day 9 범위입니다.

## 6. Day 8 one-run final E2E

Day 8 최종 종결 검증은 관리자 PowerShell에서 repository root 기준으로 실행합니다.

```powershell
powershell -ExecutionPolicy Bypass -File .\tools\release\finish_day8.ps1 -RunServerE2E
```

Android 기기를 USB 디버깅/ADB로 연결해 설치 업데이트까지 같이 확인하려면:

```powershell
powershell -ExecutionPolicy Bypass -File .\tools\release\finish_day8.ps1 -RunServerE2E -TryAndroidADB
```

이 스크립트는 순서대로:

1. 영구 Android signing key + Ed25519 deployment key 준비/재사용
2. GitHub Actions Secrets 등록
3. Canary Secure Release 실행 및 성공 대기
4. Release manifest Ed25519 서명 검증
5. Release 모든 관리 artifact의 SHA-256/size 검증
6. 필요한 경우 Day 8 GSC Setup 실행
7. GSC Canary updater 활성화 및 dry-check
8. Wild에만 `GeumyiTechnology 0.1.4`가 실제 pre-start update 되는지 확인
9. Playground에 Technology가 생기지 않았는지 확인
10. 선택 시 Android `adb install -r` 검증
11. `day8-result.json`과 `day8-e2e.log` 생성

Technology 0.1.4는 **Day 8 updater E2E를 실제 교체로 증명하기 위한 메타데이터 버전 증가**이며, 0.1.3의 게임 로직은 변경하지 않습니다.

서버에 접속자가 1명이라도 있으면 자동 재시작을 거부합니다. Android 기존 설치본의 signer가 새 영구 signer와 다르면 데이터 손실 방지를 위해 자동 uninstall은 하지 않으며 `SIGNER_TRANSITION_REQUIRED`로 종료합니다.



## Day 8 closure status

Day 8 is closed as of 2026-09-29.

Final evidence:
- Secure Release run `36574955584`: PASS
- Canary tag: `system-2026.09.29-222513-canary`
- Windows finalizer/signing preflight CI `36574083087`: PASS
- Installer-resume hotfix CI `36576774848`: PASS
- Server-PC resume finalizer: user-confirmed `DAY 8 RESUME FINALIZER: PASS`

The finalizer PASS includes signed manifest/hash verification, GSC update API verification, Wild Technology 0.1.4 validation, Wild online confirmation, and Playground Technology isolation. Android ADB signer-transition verification remains optional and is not part of the Day-8 server-side closure gate.

Day 9 owns transaction journaling, post-start health gating, automatic rollback, and failure-injection testing.
