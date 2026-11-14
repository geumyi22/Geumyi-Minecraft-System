# GSC 5.1.0 개발 상태 및 GitHub 인수인계 — 2026-11-15

> **후속 조치 — 개인용 Stable 게시 완료 (2026-11-15 02:11:58 KST):** 아래의 “GitHub CI 실패·Draft”는 **개발 당시의 이력**입니다. Windows 테스트가 사용하던 `RUNNER~1` 경로 별칭 문제를 테스트 fixture에서 정규화해 수정했으며, 이후 [System CI #43618596986](https://github.com/geumyi22/Geumyi-Minecraft-System/actions/runs/43618596986)와 [정확한 릴리스 CI #43619416741](https://github.com/geumyi22/Geumyi-Minecraft-System/actions/runs/43619416741)(21/21 SUCCESS)이 통과했습니다. [**GSC 5.1.0 — 개인용 Stable**](https://github.com/geumyi22/Geumyi-Minecraft-System/releases/tag/gsc-v5.1.0)을 11개 서명/무결성 자산과 함께 게시했습니다. 정확한 SHA는 `a3f24700049ac99b5fb2b66e5fe8bc441f389a1d`. 최신 상태는 [5.1 Stable 릴리스 검증 보고서](GSC-510-STABLE-2026-11-15.md)를 우선하세요. **운영 PC 5.1 설치·사용자 실플레이는 아직 별도 미검증**입니다.

> **현재 판정: 5.1.0 개발 기능 구현 및 로컬 QA 기록 있음 / GitHub Windows CI 실패 / Draft·미병합·미배포.** 이 문서는 기존 운영 GSC 5.0.0을 자동으로 교체하거나 5.1.0을 Stable로 승격하는 승인·증빙이 아닙니다.

## 버전·브랜치 구분

| 구분 | 근거 및 상태 |
| --- | --- |
| 공개 GSC 개인용 Stable | [GSC 5.0.0](https://github.com/geumyi22/Geumyi-Minecraft-System/releases/tag/gsc-v5.0.0), 2026-11-08 게시. 기존 자산·서명·태그 유지 |
| 5.0 로컬 유지보수 기반 | [PR #63](https://github.com/geumyi22/Geumyi-Minecraft-System/pull/63), 운영자 실플레이 확인이 있는 기반. 별도 커밋·바이너리 |
| **5.1 개발본** | [PR #64](https://github.com/geumyi22/Geumyi-Minecraft-System/pull/64), `feature/personal-server-manager`, 최초 5.1 구현 커밋 `d119d1ea70f11894e45fb1ec808dbc7b1256db1d` — **Draft / 미병합** |
| 기본 `main` | 기존 4.x 기반 소스와 이력/운영 상태 문서. 5.0/5.1 실행 코드 미병합 |
| 기존 GSCM | 이전 모바일 앱의 독립적인 릴리스. 이번 5.1 개발로 실제 모바일 설치본 교체 없음 |

**소스 출처 주의:** 5.1 QA 문서·JSON에 나오는 `77647c661dc161f174b1e04b259fbd34526b4a85`는 **5.1 개발 브랜치가 출발한 5.0 유지보수 기반 커밋**입니다. 5.1 기능을 처음 커밋한 GitHub HEAD는 위 `d119d1ea...`입니다. 기존 로컬 테스트 기록을 그 HEAD에 대한 모든 CI/배포 검증이라고 해석하지 않습니다.

## PR #64에서 구현한 기능

- 일반 서버 **7종**: Paper / Spigot / Purpur / Vanilla / Fabric / Forge / NeoForge의 설치·프로필 관리. 새 Velocity까지 합쳐 **8종 설치 경로**.
- 기존 서버 가져오기, 별도 개인용 데이터 폴더 및 서버 목록, Java/PortableGit 준비, 콘솔·로그, 시작·정상 종료·재시작, 중지 상태의 설정 편집, 실제 파일을 지우지 않는 등록 해제.
- 새 GSC 소유 Velocity 생성·실행·정상 종료·재시작 및 새 Paper 백엔드 연결.
- 기존 wild/playground/other 세 Velocity는 **Windows Scheduler 실행 주체를 그대로 유지**. 기존 실행 중 프록시의 무중단 즉시 종료 기능이 아닙니다. 처음 제어 플러그인을 연결하려면 **이용자가 없는 안전한 상태에서 기존 콘솔 방식으로 한 번 정상 종료**, 오프라인 설치·인증정보 준비 후 재시작/연결 확인이 필요합니다. 기존 작업·월드·플레이어 데이터 자동 이관/수정 금지.
- [5.1 사용 안내](https://github.com/geumyi22/Geumyi-Minecraft-System/blob/feature/personal-server-manager/docs/releases/GSC-5.1.0.md) 및 [상세 QA 기록](https://github.com/geumyi22/Geumyi-Minecraft-System/blob/feature/personal-server-manager/docs/releases/GSC-5.1.0-QA.md).

## 확인된 QA와 현재 CI 차단

**개발 작업 기록상 통과:** Windows 로컬 Go 테스트·vet·Host/Client 빌드; 별도 테스트 폴더에서 7종 게임 서버 및 새 Velocity의 공식 설치와 자동 프로토콜 클라이언트 월드 진입, 콘솔/재시작/재접속/정상 종료; 격리 Velocity 4.3.1 빌드 45와 제어 브리지의 인증·PID/시작 시각 검증·정상 종료 및 재시작; HTML DOM 검사. 이는 **자동 테스트·격리 테스트**로서 실제 Microsoft 계정 인증이나 사용자가 화면에서 플레이한 E2E와 다릅니다.

**GitHub 원격 CI 현황(2026-11-15 확인): 두 실행 모두 실패.**

- [PR System CI #43612896534](https://github.com/geumyi22/Geumyi-Minecraft-System/actions/runs/43612896534) — `GSC 5.1.0 / Go test`, `gsc-reproducibility / Go tests` 실패, 의존 종합 작업 실패, Setup 조립 작업 건너뜀.
- [브랜치 push Day 11 Host Test #43612856597](https://github.com/geumyi22/Geumyi-Minecraft-System/actions/runs/43612856597) — `build-host-test`의 Go 테스트 실패.
- CI 로그의 공통 실패: `TestInstancesImportAdditionalJavaServerKinds` (Spigot 실행 명령 검증), `TestInstancesDirectJavaUsesUTF8AndLeavesCustomScriptsUntouched`의 Forge/NeoForge (서버 폴더 밖 경로로 판단), `TestInstancesRealSubprocessStopRestart`, `TestInstancesGSCVelocityConsoleShutdownAndReceipt` (실제 서버 폴더 경로 불일치 판단). **경로 정규화/Windows Runner 환경 영향 가능성은 조사 필요하며 근본 원인 확정 전까지 CI 결함 또는 기능 정상이라고 단정하지 않습니다.**

**배포 차단:** CI PASS와 운영 설치·복구 및 실제 기존 Scheduler 세 프록시 전환/실플레이 확인 전까지 PR #64를 병합하거나 공개 5.1 Stable을 생성하지 않습니다.

## 향후 필요한 항목과 보존 원칙

1. Windows CI 실패 재현·원인 수정: 테스트의 실제 경로 비교, Spigot 실행 argv, Forge/NeoForge 로더 인수 파일·프로세스 인수 처리 및 회귀 검사. **안전 검증을 삭제하거나 무력화해서 녹색 CI로 만들지 않음**.
2. 정확한 최종 커밋 기준 Go 테스트·vet·CI/실행 파일 식별자·Setup 설치/복구 검증.
3. 사용자 UI 클릭·표시, 실제 Microsoft 계정 접속, 기존 Velocity 제어 브리지 최초 연결/종료/재시작, Java·Bedrock 연결, 다중 접속·장시간 운영 등은 그때 필요한 범위에서 별도 QA.
4. 기존 GSC 5.0 운영 빌드·월드·설정·백업·Windows Scheduled Tasks와 5.0 공개 릴리스 자산을 **그대로 유지**. 테스트용 관리 폴더 외의 운영 환경에 무단 적용하지 않음.

기존 [GSC 5.0 운영 상태(2026-11-10)](GSC-500-STATUS-2026-11-10.md)는 5.0 당시 검증 결과로 보존하며, 이 문서는 5.1 개발 현황을 분리해 추가한 것입니다.
