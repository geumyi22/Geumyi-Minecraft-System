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
- GitHub Actions [Geumyi one-time repository closeout](https://github.com/geumyi22/Geumyi-Minecraft-System/actions/workflows/geumyi-project-closeout-cleanup.yml) 는 증거 문서에서 참조하는 11자리 Workflow 실행 ID 및 최신 96시간 실행과 워크플로별 최근 3개 실행을 유지하며, 오래된 기록을 최대 1,850개 삭제하도록 설계됐다. 실제 결과는 해당 워크플로 결과/산출물 확인 필요.
- 오래된 작업용 `day8-*/day9-*/day10-*/day11-*` 브랜치들은 `main`과 몇 개 보존 브랜치, 열린 PR 및 원본 SHA 비교를 제외하고 삭제 대상이다. 원격 브랜치 정리 결과는 실제 작업 로그 기준으로 확정한다.
- 특정 오래된 베타 GSC 4.3.3~4.3.6과 **배포 금지된 4.3.9-rc.1 draft**만 릴리즈 삭제 후보. `mc-2026.09.26-v3`, `system-2026.10.07-day11-gsc438-beta`, `gsc437-beta` 등 핵심 배포·복구 파일은 유지. 삭제 대상 릴리즈의 Git 태그는 안전을 위해 유지한다. 실제 삭제 개수는 작업 로그 기준.
- 이 기록에 이미 링크된 CI 실행의 로그와 artifact를 삭제하면 해당 증거 접근이 소실되므로 자동 보존 집합을 이용한다. 이것도 100% 모든 종전 외부 참조를 검출한다는 보장은 없다.

## PC 최종 청소

별도 `Geumyi-FINAL-PC-Cleanup.zip`의 `Geumyi_FINAL_PC_CLEANUP.cmd` 실행: **메뉴 1 사전 확인, 메뉴 2 영구 삭제, 메뉴 3 자체 시험**. 현재 사용자 TEMP/TMP/LocalAppData Temp의 바로 하위에서 명확히 `Geumyi-Day1~12` 테스트 임시폴더만 대상으로 한다. 보호 파일/디렉터리, junction, 생성 후 최근 60분 내 변경, 1 GiB 초과 등은 자동 제외한다. Windows 휴지통을 거치지 않으며 삭제는 되돌릴 수 없다.

**PC 명령은 여기서 사용자의 Windows PC에 직접 실행한 적이 없다.** 각 PC에서 사용자가 직접 실행해야 하고, 데스크톱/다운로드/실제 서버 데이터/Golden 백업/GSC 설정/설치 파일/리소스팩을 영구삭제 대상으로 삼지 않는다. 모든 사전 스캔/정리는 해당 PC만 처리한다.

## 다음 변경 원칙

1. 장애가 없다면 Day13 개발 없음; 서버 현재 상태 유지.
2. 새로운 운영 버전 교체 시: 백업 존재 여부 확인 → 서명/해시 검증 → 제한 배포 → 정상 기동 확인 → 복구 계획.
3. Golden 백업/현재 월드/운영 설정/암호 및 토큰은 소프트웨어 정리 대상으로 간주하지 않는다.
4. 필요할 때만 GitHub Action 및 릴리즈 재정리. 소규모 운영 수락과 강제 Stable 게이트 통과를 혼동하지 않는다.

관련: [DAY-TIMELINE.md](DAY-TIMELINE.md) · [FINAL-RELEASE-GATES.json](FINAL-RELEASE-GATES.json) · [DAY12-SMALL-SERVER-4CHECK-OPERATIONS-20261011.md](DAY12-SMALL-SERVER-4CHECK-OPERATIONS-20261011.md).
