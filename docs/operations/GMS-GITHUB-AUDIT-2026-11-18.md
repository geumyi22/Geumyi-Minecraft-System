# GMS / GSC GitHub 전체 정리 점검 — 2026-11-18

> 대상: `geumyi22/Geumyi-Minecraft-System`의 **GitHub 원격 저장소**. 연결된 Windows PC의 Desktop Commander는 이번 점검 시 오프라인이므로 로컬 작업 폴더·가동 중 서비스·기존 월드/백업 파일을 직접 검사하거나 변경하지 않았습니다. 아래 결과는 GitHub 메타데이터·파일 트리와 정확한 CI/PR/릴리스 기록을 기준으로 한 사실입니다.

## 1. 릴리스·실제 설치·소스 구분

| 구분 | 현재 상태 |
| --- | --- |
| **공개 최신 GSC 개인용 Stable** | [GSC 5.1.1](https://github.com/geumyi22/Geumyi-Minecraft-System/releases/tag/gsc-v5.1.1), 2026-11-15 KST 게시; 태그 SHA `bf422a1d6225a748a1387f95baa09e1515e1d558` |
| 5.1.1 릴리스 검증 | [GitHub CI #43623012808](https://github.com/geumyi22/Geumyi-Minecraft-System/actions/runs/43623012808) **21/21 SUCCESS**, Windows Setup, Ed25519 서명·SHA/출처 확인. 모든 실서버 E2E 완료는 아님 |
| **실제 서버 PC 설치/플레이** | 가장 최근 사용자 확인은 `5.0.0`의 로컬 `maintenance-c39ecd67...` 빌드에서 실플레이 정상. 5.1.1 운영 PC 설치·사용자 실플레이는 별도 미확인 |
| **GitHub `main`** | 여전히 GSC **4.x 복구 기반 소스** 및 문서. 5.x 실행 코드를 `main`에 병합하거나 새 Stable을 임의 재배포하지 않음 |
| 후속 콘솔 후보 | [개발 추적 이슈 #66](https://github.com/geumyi22/Geumyi-Minecraft-System/issues/66): **5.1.2는 아직 개발·실게임 검증·릴리스되지 않음** |

기존 GSC [5.0.0](https://github.com/geumyi22/Geumyi-Minecraft-System/releases/tag/gsc-v5.0.0), [5.1.0](https://github.com/geumyi22/Geumyi-Minecraft-System/releases/tag/gsc-v5.1.0), [5.1.1](https://github.com/geumyi22/Geumyi-Minecraft-System/releases/tag/gsc-v5.1.1) 태그·서명·바이너리·이력은 모두 보존합니다. 이전 GSCM 및 Bedrock 네트워크·플러그인 릴리스도 관련 QA·복원 출처가 있으므로 자동 삭제 대상이 아닙니다.

## 2. 저장소 파일·불필요 항목 조사

2026-11-18 조회 기준 `main` Git 트리: 총 1,958개 Git 항목(폴더 포함), 그중 **파일 1,731개**, 합산 약 **41.5 MB**(Git tree의 등록 blob 크기 합산). `tree.truncated=false`.

파일명/경로 기반 일괄 검사에서 **추적 중인 명백한 임시·편집 백업·로그·빌드 캐시·`node_modules`·`dist`·덤프 산출물**은 발견하지 못했습니다. 이는 **내용까지 일일이 읽은 데이터 품질 검사 또는 모든 파일의 사용 여부 증명은 아닙니다.**

따라서 이번 정리에서 **삭제를 확정할 수 있는 추적 파일은 0개**입니다. 특별한 근거 없이 아래를 삭제하지 않습니다.

- 기존 Day 1–12·Canary 문서, 보안/인증/롤백 보고서, 버전별 QA 근거
- `FINAL-RELEASE-GATES.json`, 소스 재현/빌드 설명, 배포 서명·승인 근거, 런타임에 임베드하는 필수 플러그인 JAR
- 오래된 릴리스, 태그, 미병합 개발 PR/브랜치(해당 소스가 `main`에 없을 수 있음)

**대신:** 생성 산출물과 로컬 비밀 정보가 Git에 잘못 추가되지 않도록 `.gitignore`를 정리하고, README·문서 목차에서 충돌하는 “최신” 표시를 바로잡습니다. 원본 역사적 문서 내용은 보존합니다.

## 3. PR·브랜치 점검

2026-11-18 점검 시작 시 **브랜치 29개**, **열린 PR 13개**(`#47–#54` 중 일부, `#60–#65`)였고, 열려 있는 일반 Issue는 0개였습니다. 이번 작업으로 **후속 콘솔 개발용 Issue #66**을 새로 만들었습니다.

이 PR들은 대부분 **Draft 또는 여러 단계로 이어진 보안·5.0→5.1 소스 개발 기록**입니다. 특히 [PR #65](https://github.com/geumyi22/Geumyi-Minecraft-System/pull/65)는 5.1.1의 이전 경로 수정 소스를 보존합니다. 공개 태그가 있다고 `main`에 해당 실행 코드가 자동 포함된 것은 아니므로, 병합·닫기·브랜치 삭제를 일괄 실행하지 않습니다.

이전 [Issue #56](https://github.com/geumyi22/Geumyi-Minecraft-System/issues/56)의 *Windows Scheduler를 GSC 직접 소유로 전환* 연구는 `not planned`로 종료돼 있습니다. **현재 Issue #66은 Scheduler 소유권을 유지한 인증된 콘솔 명령 연결**이라는 별도 기능으로 추적합니다.

## 4. Velocity 콘솔 후보 QA 정확한 범위

- [`feature/velocity-console-20261115`](https://github.com/geumyi22/Geumyi-Minecraft-System/tree/feature/velocity-console-20261115), HEAD `f6033bc5bfe0b26c5e5bd5c597f2dbe10b6f9327`.
- [공개 GSC 5.1.1 태그](https://github.com/geumyi22/Geumyi-Minecraft-System/tree/gsc-v5.1.1)와 직접 비교 시 **새 `.github/workflows/velocity-console-candidate.yml` 1개만 변경**. 실제 Velocity 콘솔·Host 명령·Java 브리지 실행 코드의 추가 변경은 없음.
- [성공 CI #43672360070](https://github.com/geumyi22/Geumyi-Minecraft-System/actions/runs/43672360070)의 단일 작업 이름은 **“Export tracked source only (no production files)”**. `git archive` ZIP·SHA-256 검증 자료를 업로드하는 소스 검토용 작업이며, **명령어 입력/전송·정상 종료·E2E의 PASS 근거가 아님**.
- 새 후속 버전의 정상 종료/재시작은 로컬 인증된 Velocity 브리지, 접속자 보호, 오류 시 강제 종료 금지, 기존 프록시 오프라인 최초 연결 검증까지 완료돼야만 릴리스 가능.

## 5. 이번 정리와 운영 원칙

문서 진입점과 변경 이력을 현재 공개 릴리스 순서로 정리해 낡은 “최신” 문구가 실제 버전 선택을 혼동시키지 않도록 합니다. 오래된 이력은 정확한 기준 날짜를 붙여 남깁니다. 재발 방지용 추적 이슈 #66을 사용합니다.

**보호 대상:** 사용자의 마인크래프트 월드, 플레이어 파일·설정·백업, 기존 Windows Scheduled Tasks 3개, GSCM 앱, 공개 Stable 서명·태그, PR의 검증 근거. 이 GitHub 정리 작업은 **이 대상에 대한 실행·설치·삭제·강제 종료 작업이 아닙니다.**

**다음 확인 조건:** 5.1.2 개발본은 실제 구현·회귀 테스트와 검증된 정확한 커밋의 CI 및 필요 범위의 실플레이 증거가 있어야 개인용 Stable 후보가 됩니다. 나중에 중복 문서를 합치거나 오래된 브랜치를 삭제할 때는 참조·부모 브랜치·릴리스 태그·PR의 소스 보존 여부를 구체적으로 다시 확인합니다.
