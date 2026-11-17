# GMS / GSC 운영 자료 및 과거 기록

**최신 공개 개인용 Stable (2026-11-18 확인): [GSC 5.1.1](https://github.com/geumyi22/Geumyi-Minecraft-System/releases/tag/gsc-v5.1.1).** 공개 CI/서명·실제 PC 설치·실플레이는 서로 구분합니다. `main`은 4.x 복구 기반 코드이며 최신 5.1.1 실행 코드는 공개 릴리스 태그에 있습니다.

- [**GitHub 전체 점검·파일/브랜치/PR 정리 (2026-11-18)**](GMS-GITHUB-AUDIT-2026-11-18.md)
- [**GSC 5.1.1 개인용 Stable 설치 이전 오류 수정·최종 CI**](GSC-511-MIGRATION-HOTFIX-2026-11-15.md)
- [5.1.2 개발 후보: 기존 Scheduler Velocity 인증 콘솔·정상 종료/재시작](https://github.com/geumyi22/Geumyi-Minecraft-System/issues/66) — 아직 실행 코드·E2E 미완료
- [GSC 5.1.0 릴리스 검증 (과거)](GSC-510-STABLE-2026-11-15.md) · [개발 당시 CI 오류·수정 전 현황](GSC-510-DEVELOPMENT-STATUS-2026-11-15.md)
- [GSC 5.0.0 사용자 실플레이·로컬 유지보수 기록](GSC-500-STATUS-2026-11-10.md) · [5.0 유지보수 Draft PR #63](https://github.com/geumyi22/Geumyi-Minecraft-System/pull/63)

## 2026-10-11 이전 운영 자료 (보존)

**2026-10-11:** Day 12는 소규모 운영 기준으로 마감됐습니다. 문제 없으면 현재 설치와 백업은 그대로 유지합니다. 이후 진행한 GSC 4.5.2 Canary 개발은 별도의 미완료 Draft PR이며, 운영 Stable에 적용됐다는 의미가 아닙니다.

- [**2026-10-24 운영 상태·PR 정리·인수인계**](GMS-CURRENT-STATUS-2026-10-24.md) — 소규모 운영 마감 이후 Draft Canary 개발과 미승인 게이트 구분
- [2026-10-11 이전 통합 패키지 Stable — GSC 4.5.1 / GSCM 1.5.1+151](https://github.com/geumyi22/Geumyi-Minecraft-System/releases/tag/system-2026.10.11-stable-gsc451-gscm151)
- [프로젝트 종료·GitHub 정리 기록](../../PROJECT-CLOSEOUT-2026-10-11.md)
- [Day 1~12 완료 현황](../../DAY-TIMELINE.md)
- [Day 12 실운영·복구 절차](../../DAY12-LIVE-RUNBOOK.md)
- [정식 서명 Stable 보안 게이트](../../FINAL-RELEASE-GATES.json)
- [GSC 4.5.1 Ed25519 서명 Beta 업데이트](https://github.com/geumyi22/Geumyi-Minecraft-System/releases/tag/system-2026.10.11-gsc451-signed-beta.1) — 기존 Beta 공개키 동일·수동 설치 승인
- [PC 임시 파일 안전 청소](../../DAY1-12-PC-CLEANUP-GUIDE.md)
- [4.5.1/1.5.1 실기기 설치·회귀 테스트](RELEASE-4.5.1-1.5.1-SMOKE-CHECKLIST.md)

**유지보수 원칙:** 백업 확인 → 설치 파일 출처와 SHA-256 검증 → 한 대씩 설치 → Java·Bedrock·GSCM 확인 → 이상 시 롤백. 2026-10-11 이전 통합 패키지는 수동 설치용이었습니다. 당시 문서에서의 실기기 확인 버전 GSC 4.3.8/GSCM 1.1.5+117은 역사적 기준이며, 최신 GSC 5.0 사용자 실플레이 확인과 구분합니다. iOS IPA는 미서명입니다.
