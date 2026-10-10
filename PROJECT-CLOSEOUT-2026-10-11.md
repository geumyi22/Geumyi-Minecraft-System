# Geumyi Minecraft System — 소규모 운영 프로젝트 종료 정리

**기준: 2026-10-11, 사용자 요청에 따른 기능 개발 및 테스트 종료/정리.**

## 운영 확정 기준

- 운영 GSC **4.3.8**, GSCM **1.1.5+117**. 네 서버 프로필은 Wild / Playground / Other / Lobby. Other 서버는 사용자의 지시에 따라 추가 실행 시험을 면제하고, 나머지 세 서버 공통 기능의 **운영자 승인으로만** 기록한다.
- Java 및 Bedrock 연결/이동, 리소스팩, GSC 및 GSCM 기본 운영 기능은 기존 실기기 확인 및 사용자 최종 승인에 따라 **소규모 서버 운영 기준 통과**. 실제로 수행하지 않은 검증을 새롭게 수행했다고 기록하지 않는다.
- Golden full protected backups **4/4**, known-good cache SHA-256/size **84/84**, Windows CI에서 실제 GSC+Paper 프로세스 장애 복구 및 GSC update/rollback PASS (비운영 CI 범위).
- 내부 6개 온라인 Java/RCON 포트: 사용자 Windows 26220에서 native raw state=0 listener-signature+Paper PID+loopback 일치; 네 가지 LAN/Tailscale v4/v6에서 0/8 private TCP reachable with positive controls. Other의 2개 포트는 당시 OFFLINE이라 실측하지 않았다.
- 방화벽 38개 광범위 Allow 후보 중 15개가 Public 프로필 관련, 각 규칙의 유효 필요성은 미확정. GSC 관련 3개 디렉터리에 Users create-allow inherited ACE 존재, 실제 일반 사용자 effective ACL 경계는 미판정. 소스 코드 안전성은 별도 Windows CI로 개선됐지만 **운영 GSC 4.3.8에 아직 설치되지 않음**.

## 종료의 정확한 의미

**프로젝트 기능 개발 및 반복 테스트 종료 / 소규모 운영 기준 수락**이다. **정식 Stable 릴리즈 발행/서명 완료가 아니다.** `FINAL-RELEASE-GATES.json`의 `backend_ports_private=FAIL_UNVERIFIED_NATIVE_OWNER_ADDRESS`, `stable_release_allowed=false`, `maintenance_mode_allowed=false`를 거짓 통과로 바꾸지 않는다. 운영을 시작하거나 계속할 수 있다는 사용자의 판단은 별개의 정책 승인이다.

중요한 새 보안 문제, 백업 오류, 데이터 손상, 버전 호환성 문제가 실제로 생기는 경우에만 새로운 검증·패치를 시작한다. 사용자 승인으로 이미 완료된 기능 테스트는 반복하지 않는다.

## GitHub 저장소 보관 및 정리

- 원본 `main` 커밋 히스토리는 **rewrite/force-push 금지**. 오래된 개별 커밋을 없애려는 이유로 서명된 릴리즈/백업 근거를 깨지 않는다.
- 정리 전 브랜치 헤드와 릴리즈 자산 메타데이터는 `docs/archive/2026-10-11-before-cleanup-inventory.json`에 저장했다. 메타데이터만으로 삭제된 Git 객체의 영구적 보존을 보장하지는 않는다.
- 안전한 핵심 릴리즈만 남겨 실제 CI 기록·브랜치·릴리즈 정리를 실행했고, 역사적 일회성 워크플로 소스는 `docs/archive/workflows/`에 보관했다. 실측 값과 각 GitHub Actions 실행 링크는 아래 최종 결과 표에서 확인한다.
- 이 기록에 이미 링크된 CI 실행의 로그와 artifact를 삭제하면 해당 증거 접근이 소실되므로 자동 보존 집합을 이용한다. 이것도 100% 모든 종전 외부 참조를 검출한다는 보장은 없다.

## 최종 GitHub 실제 정리 결과 (2026-10-11)

| 항목 | 정리 전 | 최종 확인 | 의미 |
|---|---:|---:|---|
| GitHub Actions 실행 이력 | 2,332개 | **808개** | 초기 총수 대비 최소 1,524개 감소; 세 차례 안전 정리 워크플로 모두 SUCCESS |
| 작업용 브랜치 | 48개 | **5개** | 43개 삭제, main 및 Day 8~11 참고 기준 브랜치 네 개 유지 |
| 릴리즈 | 15개 | **10개** | 4.3.3~4.3.6 중간 베타 4개와 미배포 RC1 초안 1개 삭제, Git 태그 보존 |
| 실행 워크플로 | 55개 | **18개** | 37개 일회성 정의를 `docs/archive/workflows/*.yml.txt`로 무손실 소스 보관 |

- Actions 작업 [1차 #38079060935](https://github.com/geumyi22/Geumyi-Minecraft-System/actions/runs/38079060935), [2차 #38079530638](https://github.com/geumyi22/Geumyi-Minecraft-System/actions/runs/38079530638), [최종 #38079942304](https://github.com/geumyi22/Geumyi-Minecraft-System/actions/runs/38079942304) 모두 **SUCCESS**. 삭제 상세 목록 및 기준은 각 실행의 `geumyi-closeout-audit` artifact에 보존. 마지막 일회성 청소 워크플로 자체도 `docs/archive/workflows/`로 옮겨 재실행되지 않도록 했다.
- 남은 브랜치는 `main`, `day8-secure-release`, `day9-transaction-rollback`, `day10-four-server-live-cutover-final-ci`, `day11-protection-recovery-2`. 정확한 삭제 전 각 브랜치 HEAD SHA는 앞서 보존한 inventory를 참조한다.
- 원래 열려 있던 오래된 Day9 PR [#12](https://github.com/geumyi22/Geumyi-Minecraft-System/pull/12)는 최신 운영 버전 4.3.8 기준 불필요한 4.2.4 finalizer 후속 PR로 판정했다. 기존 CMD의 clone/pull errorlevel 보호 두 구간은 `main`에 별도 반영하고 **PR은 미병합 상태로 종료**한 뒤 작업용 브랜치를 삭제했다.
- 브랜치·Actions 기록·릴리즈 항목 삭제는 각각 **돌이키기 어려울 수 있으며** 이후 원본 run 로그/자산을 복구할 수 있다고 보장하지 않는다. `main` commit history를 강제로 삭제하거나 억지로 squash/rebase/force-push하지는 않았다.
- **삭제만으로 GitHub 저장소 물리 크기가 즉시 줄어든다고 보장하지 않는다.** GitHub의 Git object garbage collection 및 Actions 저장 용량 반영 시점은 별개다.

## PC 최종 청소

별도 `Geumyi-FINAL-PC-Cleanup.zip` (SHA-256 `9e0a9d75c0073a96632612fc02e70d18dc93bf329ef4458ff62cd40acc62cfb6`)의 `Geumyi_FINAL_PC_CLEANUP.cmd` 실행: **메뉴 1 사전 확인, 메뉴 2 영구 삭제, 메뉴 3 자체 시험**. 현재 사용자 TEMP/TMP/LocalAppData Temp의 바로 하위에서 명확히 `Geumyi-Day1~12` 테스트 임시폴더만 대상으로 한다. 보호 파일/디렉터리, junction, 생성 후 최근 60분 내 변경, 1 GiB 초과 등은 자동 제외한다. Windows 휴지통을 거치지 않으며 삭제는 되돌릴 수 없다. 실제 삭제 메뉴는 사전 격리 안전성 자체 테스트 PASS 뒤 승인 문구를 입력해야 진행한다.

**PC 명령은 여기서 사용자의 Windows PC에 직접 실행한 적이 없다.** 각 PC에서 사용자가 직접 실행해야 하고, 데스크톱/다운로드/실제 서버 데이터/Golden 백업/GSC 설정/설치 파일/리소스팩을 영구삭제 대상으로 삼지 않는다. 모든 사전 스캔/정리는 해당 PC만 처리한다.

## 다음 변경 원칙

1. 장애가 없다면 Day13 개발 없음; 서버 현재 상태 유지.
2. 새로운 운영 버전 교체 시: 백업 존재 여부 확인 → 서명/해시 검증 → 제한 배포 → 정상 기동 확인 → 복구 계획.
3. Golden 백업/현재 월드/운영 설정/암호 및 토큰은 소프트웨어 정리 대상으로 간주하지 않는다.
4. 필요할 때만 GitHub Action 및 릴리즈 재정리. 소규모 운영 수락과 강제 Stable 게이트 통과를 혼동하지 않는다.

관련: [DAY-TIMELINE.md](DAY-TIMELINE.md) · [FINAL-RELEASE-GATES.json](FINAL-RELEASE-GATES.json) · [DAY12-SMALL-SERVER-4CHECK-OPERATIONS-20261011.md](DAY12-SMALL-SERVER-4CHECK-OPERATIONS-20261011.md).
