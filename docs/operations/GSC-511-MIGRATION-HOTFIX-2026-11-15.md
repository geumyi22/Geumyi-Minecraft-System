# GSC 5.1.1 개인용 Stable — 5.0.0 Host 이전 오류 수정 (2026-11-15)

> **현재 최신 공개 개인용 Stable:** [GSC 5.1.1](https://github.com/geumyi22/Geumyi-Minecraft-System/releases/tag/gsc-v5.1.1). 2026-11-15 02:51 KST 게시. 5.0.0·5.1.0 릴리스와 바이너리는 변경하지 않았습니다. **게시 완료와 실제 사용자 PC 설치 완료는 다릅니다.**

## 실제 증상 및 확인된 원인

- 사용자가 5.1.0 Setup을 실행할 때 `existing Host identity/health unverified; upgrade stopped before service changes`가 표시됨.
- 그때 실제 Host 서비스가 `Stopped`였고 Health API에 연결할 수 없었음. 이 단계의 설치 차단은 기존 서비스 신원을 검증하지 못했기 때문에 발생. 해당 오류만으로 설치기가 서비스를 종료했다고 판단하지 않음.
- 이후 사용자 확인: 기존 서비스 `Running`, Host Health `ok=true, version=5.0.0, service=true, generation=4, build_revision=maintenance-c39ecd...`; 저장된 `role.json`은 UTF-8로 읽었을 때 `role=3, version=5.0.0`으로 정상 파싱됨.
- 공식 5.1.0 Setup 소스의 `gsc5MigrationDecision`은 기존 호스트를 **4.5.1 또는 5.1.0만 허용**해, 위의 정상적인 5.0.0 버전/Health 일치 상태여도 다음 보호 검사에서 업그레이드를 차단하는 문제를 확인함.

## 수정 내용

- **5.0.0과 5.1.0을 5.1.1 설치의 명시적 허용 이전 버전 목록에 추가**. 기존 Host Health가 `ok=true`, `service=true`, `generation=4`이고 저장된 역할 버전과 실제 실행 버전이 정확히 같을 때만 진행.
- 중지/미응답 Host, 저장/실행 버전 불일치, 알 수 없는 이전 버전, 4.5.2 Canary, 서비스 아닌 HTTP 응답, API 세대 불일치는 계속 **fail closed**. 기존 보안 검사를 제거하거나 우회하지 않음.
- Host Health 요청 제한 1.8초 → 5초. 서비스에 연결할 수 없을 때는 기존 Host 서비스를 먼저 정상 시작하도록 더 명확하게 표시.
- 새 회귀 테스트에는 저장된 5.0.0 역할 1·3과 실행 중 건강한 5.0.0 허용, 중지·비서비스 응답·잘못된 API 세대·버전 불일치 거절을 포함.
- GSC Host·Client·Setup 코드/설치 문구·CI 산출물 버전 **5.1.1로 일치**, 5.1.0 개발 기능은 보존.

## 릴리스·CI 검증

| 항목 | 결과 |
| --- | --- |
| 공개 Stable | [gsc-v5.1.1](https://github.com/geumyi22/Geumyi-Minecraft-System/releases/tag/gsc-v5.1.1), `draft=false`, `prerelease=false` |
| 정확한 SHA | `bf422a1d6225a748a1387f95baa09e1515e1d558` — 릴리스 타깃 및 태그 일치 |
| 정확한 GitHub 워크플로 | [Actions #43623012808](https://github.com/geumyi22/Geumyi-Minecraft-System/actions/runs/43623012808) — **21/21 SUCCESS**, 실패 0, 스킵 0 |
| Setup 검사 | 새 Windows PE 패키징, disposable Windows Host 서비스/인증 API, client-only 설치, 파일 백업·롤백 검증 통과 |
| 무결성 | 11개 공식 릴리스 자산, SHA-256 + Ed25519 배포 명세 서명, 기존 공개키 고정, Draft 재다운로드 후 동일성 재검증 |
| Windows Authenticode | **미서명**. 배포 명세의 Ed25519 서명과는 별개 |
| Setup SHA-256 | `eff96d1f4732870b7c1f5eacca8ee7a3258a5534e4f1f306b09a3b0b67282042` |
| PR | [유지보수 PR #65](https://github.com/geumyi22/Geumyi-Minecraft-System/pull/65), Draft/미병합. 릴리스 태그는 정확한 별도 브랜치에서 게시 |
| 기존 릴리스 | [5.1.0](https://github.com/geumyi22/Geumyi-Minecraft-System/releases/tag/gsc-v5.1.0), [5.0.0](https://github.com/geumyi22/Geumyi-Minecraft-System/releases/tag/gsc-v5.0.0) 태그·자산 유지 |

## 실제 운영 PC 업그레이드 전 확인 사항

**5.1.1이 공개됐지만 기존 GSC 5.0.0 실운영 PC에는 아직 설치되지 않았습니다.** 기존 사용자 PC에서의 5.0.0→5.1.1 서비스 파일 교체·기존 월드/설정의 전후 검증·라이브 롤백·실제 Minecraft 플레이는 **미실행**입니다. GitHub CI가 이러한 실제 운영 검증을 대신했다고 주장하지 않습니다.

업그레이드 전에 (1) Host 서비스·Health·저장 역할 버전 일치 재확인, (2) 월드/플레이어/백업/설정/설치 실행 파일·서비스 경로·Windows Scheduler Velocity 작업의 별도 복구 가능한 백업, (3) 실제 접속자 없는 점검 시간 확보, (4) 새 Setup의 설치 역할·야생/놀이터 경로 확인, (5) 작업 후 Host/Client·기존 프록시 및 월드 저장/플레이·백업 검증과 실패 시 원복 계획이 필요합니다.

원래 운영 프록시 세 개는 계속 Windows Scheduler 소유이며 이번 유지보수로 직접 소유권을 넘기거나 강제 종료하지 않습니다. 기존 5.0.0 Host가 정상이라면 검증 전까지 그대로 사용하는 것이 안전합니다.

릴리스 소스 참고: [5.1.1 배포 설명](https://github.com/geumyi22/Geumyi-Minecraft-System/blob/gsc-v5.1.1/docs/releases/GSC-5.1.1-STABLE.md).
