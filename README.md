# Geumyi Minecraft System

> **프로젝트 종료 정리 (2026-10-11):** 일반 기능 개발과 반복 테스트는 소규모 서버 운영 기준으로 마감했습니다. GitHub/PC 정리 기록과 유지할 복구 자산은 [PROJECT-CLOSEOUT-2026-10-11.md](PROJECT-CLOSEOUT-2026-10-11.md)에 있습니다. 정식 Stable 릴리즈의 엄격한 보안 게이트는 아직 통과하지 않았습니다.

**최신 수동 설치 패키지:** [GSC 4.5.1 / GSCM 1.5.1+151 Stable](https://github.com/geumyi22/Geumyi-Minecraft-System/releases/tag/system-2026.10.11-stable-gsc451-gscm151) (2026-10-11 공개, GitHub Latest). 마지막 실제 운영 기기 확인은 GSC 4.3.8 / GSCM 1.1.5+117이며, 자동 Stable 배포용 서명 manifest는 별도입니다.

GSC 4.5.1 및 GSCM 1.5.1+151 Stable 수동 설치 빌드 대상의 소스·복구 근거·CI·리소스팩을 모은 저장소입니다. **원본 그대로 회수한 소스와 바이너리 기준으로 재구성한 소스를 구분해서 기록합니다.**

| Component | Baseline | Path | Recovery status |
|---|---|---|---|
| GSC | 4.5.1 package / 4.3.8 last live-verified | GSC/ServerCenter | Client/Host split, 4.3.7→4.3.8 Client/Host self-update, Protection & Recovery 2.0 and Day-11 Final E2E verified |
| GeumyiStatusAgent | 0.5.4 | GSC/StatusAgent | Full 9-file Java source reconstruction; JDK 21 clean build succeeds |
| GSCM | 1.5.1+151 package / 1.1.5+117 last live-verified | GSCM | Protection & Recovery 2.0 controls included; final two requested Day-11 GSCM device checks user-confirmed PASS |
| GST | 1.1.1 HOTFIX | Plugins/GeumyiServerTools | Exact HOTFIX/overlay delta recovered and matched against final deployed JAR; legacy 0.1.5 core remains binary-only |
| GDS | 1.1.1 | Plugins/GeumyiDiscordStatus | Recovered full plugin source, stubs and tests |
| GeumyiNetwork | 0.1.0 | Plugins/GeumyiNetwork | Day 10 four-server transfer/last-location routing plugin; Java host E2E verified |
| GeumyiLobby | 0.1.0 | Plugins/GeumyiLobby | Day 10 Lobby selector/protection plugin; Java host E2E verified |
| GeumyiTechnology | 0.1.4 | Plugins/GeumyiTechnology | Day-8 E2E marker release; gameplay logic remains the reconstructed/verified 0.1.3 baseline, with version metadata aligned to 0.1.4 |
| GeumyiChemistry | 0.4.1 | Plugins/GeumyiChemistry | Reconstructed and semantically verified against deployed 0.4.1; not labeled untouched original source |
| Wild server | Paper 26.3 | Servers/Wild | 2026-09-27 live E2E evidence captured; sanitized current server.properties tracked |
| Playground server | Paper 26.3 | Servers/Playground | 2026-09-27 live E2E evidence captured; sanitized current server.properties tracked |
| Other server | Paper 26.3 | Servers/Other | Day 10 four-server target; Java routing/location restore verified on host |
| Lobby server | Paper 26.3 | Servers/Lobby | Day 10 central entry server; reboot/startup and Java routing verified on host |
| Resource packs | Java 26.3 / bundled Bedrock | ResourcePacks | Recovered expanded assets and Wild Geyser mapping |


**전체 문서 찾아보기:** [통합 문서 목차](docs/README.md) · [Day 4~11 기록](docs/history/INDEX.md) · [Day 12 단계별 보고서](docs/day12/INDEX.md) · [아키텍처·복구·보안](docs/reference/INDEX.md). CI와 운영 도구가 직접 참조하는 핵심 파일만 최상위에 유지합니다.

## 프로젝트 일차 기준

일차 번호/완료 상태는 [DAY-TIMELINE.md](DAY-TIMELINE.md)를 **단일 기준**으로 사용합니다.

| 범위 | 상태 |
|---|---|
| Day 1~9 | ✅ 완료 |
| Day 10 | ✅ Java + Bedrock four-server/Lobby real-client E2E 완료 |
| Day 11 | ✅ 완료 — GSC 4.3.8 / GSCM 1.1.5+117, Final READ-ONLY E2E + Java/Bedrock smoke + final GSCM checks PASS |
| Day 12 | ✅ **소규모 운영 기준 마감** — 4/4 Golden, 84/84 cache, Java/Bedrock/GSC/GSCM 운영자 승인, Windows CI 복구 PASS. ⚠️ 정식 Stable 서명 배포·일부 실효 보안 검증은 **별도 차단 유지** |

Day 4는 누락된 번호가 아니라 **새 구현 없이 실서버 E2E 검증/마감을 수행한 milestone**입니다. Day 8과 Day 9는 모두 완료 상태이며, 각 E2E PASS는 완료의 근거입니다.

## 사용 방법

- GSC: [빌드 안내](GSC/ServerCenter/BUILD.md)
- GSCM: [빌드 안내](GSCM/BUILD.md)
- GDS: [빌드 안내](Plugins/GeumyiDiscordStatus/BUILD.md)
- StatusAgent: [복구 근거](GSC/StatusAgent/RECOVERY.md)
- GST / Technology / Chemistry: 각 컴포넌트의 `README.md`와 `RECOVERY.md`에서 원본/재구성 범위를 구분합니다.
- 리소스팩: [구성 및 패키징](ResourcePacks/README.md)
- 전체 일차/상태 단일 기준: [DAY-TIMELINE.md](DAY-TIMELINE.md)
- Day 4 실서버 검증/마감: [DAY4-E2E-REPORT.md](docs/history/day-04/DAY4-E2E-REPORT.md)
- GSC/GSCM 안정화 검증: [DAY5-STABILITY-REPORT.md](docs/history/day-05/DAY5-STABILITY-REPORT.md)
- 전체 컴포넌트 자동 빌드/CI 검증: [DAY7-CI-REPORT.md](docs/history/day-07/DAY7-CI-REPORT.md)
- Day 8 보안 Release/자동 업데이트 완료 보고: [DAY8-RELEASE-REPORT.md](docs/history/day-08/DAY8-RELEASE-REPORT.md)
- Day 9 transaction/backup/rollback 완료 상태: [ROADMAP.md](ROADMAP.md#day-9--transaction--backup--rollback--완료)
- Day 10 Full E2E/Lobby 네트워크 고정 계획: [DAY10-PLAN.md](docs/history/day-10/DAY10-PLAN.md)
- Day 10 실제 서버 검증 결과: [DAY10-E2E-REPORT.md](docs/history/day-10/DAY10-E2E-REPORT.md)
- Day 11 Protection & Recovery 2.0 실서버 검증: [DAY11-PHASE7-REPORT.md](docs/history/day-11/DAY11-PHASE7-REPORT.md)
- Day 11 최종 마감 보고: [DAY11-FINAL-REPORT.md](docs/history/day-11/DAY11-FINAL-REPORT.md)
- Day 12 repository/live 진행 분리: [DAY12-REPO-PROGRESS.md](DAY12-REPO-PROGRESS.md)
- Day 12 나중에 실행할 순서: [DAY12-LIVE-RUNBOOK.md](DAY12-LIVE-RUNBOOK.md)
- Day 12 Golden Baseline: [FINAL-BASELINE.json](FINAL-BASELINE.json), [FINAL-VERSION-MATRIX.md](FINAL-VERSION-MATRIX.md), [FINAL-NETWORK-TOPOLOGY.json](FINAL-NETWORK-TOPOLOGY.json)
- 이후 작업 순서와 장기 계획: [ROADMAP.md](ROADMAP.md)
- 자동 빌드/Release/서버 자동 업데이트/rollback 장기 설계: [DEPLOYMENT-ARCHITECTURE.md](docs/reference/DEPLOYMENT-ARCHITECTURE.md)

완성 EXE/JAR/APK/IPA/ZIP은 [기존 Release](https://github.com/geumyi22/Geumyi-Minecraft-System/releases/tag/mc-2026.09.26-v3)에 유지합니다. 운영 토큰·RCON 비밀번호·키스토어·월드·개인 로그는 Git에 넣지 않습니다.

저장소는 Public 상태이므로 현재 트리와 Git 히스토리의 개인정보/시크릿 점검 결과는 [SECURITY-NOTES.md](docs/reference/SECURITY-NOTES.md)에 별도로 기록합니다. 자세한 복구 근거는 [RECOVERY-REPORT.md](docs/reference/RECOVERY-REPORT.md), [VERSION-MATRIX.md](VERSION-MATRIX.md), [SOURCE-MANIFEST.json](SOURCE-MANIFEST.json)을 확인하세요.


## 최신 Stable 빌드

- [**GSC 4.5.1 / GSCM 1.5.1+151 — 최신 수동 설치 Stable**](https://github.com/geumyi22/Geumyi-Minecraft-System/releases/tag/system-2026.10.11-stable-gsc451-gscm151): Windows GSC Setup/Host/Client, Android 서명 APK, iOS **미서명** IPA 및 SHA-256·출처 증빙 총 10개 파일. GitHub Latest 지정.
- GSC 4.5.1은 ViaVersion/ViaBackwards 다운로드용 Staging과 **서버 종료 후 명시적 오프라인 적용**을 분리했습니다. GSCM 1.5.1은 실행 시 새로운 버전 **확인** 및 설정의 수동 확인을 추가했습니다. Android 자동 설치나 iOS 미서명 IPA 설치를 지원하지 않습니다.
- [원본 CI #38084637534](https://github.com/geumyi22/Geumyi-Minecraft-System/actions/runs/38084637534)의 빌드·서명·체크섬은 통과, 초안 태그 조회 404로 마지막 게시 단계 실패. [후속 공개 #38085210886](https://github.com/geumyi22/Geumyi-Minecraft-System/actions/runs/38085210886)은 SUCCESS.
- 최신 GitHub 수동 설치 Stable은 **서명된 `deployment-stable.json`이 아닙니다.** 엄격한 자동 Stable 업데이트/보안 게이트는 계속 차단되며 실제 서버·휴대폰 설치/E2E 완료로 간주하지 않습니다.
- [이전 4.5.0/1.5.0+150 릴리즈(이력 보존)](https://github.com/geumyi22/Geumyi-Minecraft-System/releases/tag/system-2026.10.11-stable-gsc450-gscm150) · [4.5.1/1.5.1 실기기 검증 체크리스트](docs/operations/RELEASE-4.5.1-1.5.1-SMOKE-CHECKLIST.md)

