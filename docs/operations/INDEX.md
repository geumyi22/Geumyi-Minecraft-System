# 금이 마인크래프트 시스템 — 최종 운영 안내

**현재 기준 (2026-11-10):** GSC 최신 공개 개인용 Stable은 [GSC 5.0.0](https://github.com/geumyi22/Geumyi-Minecraft-System/releases/tag/gsc-v5.0.0)입니다. 2026-11-08 실제 Windows PC에 적용된 별도 유지보수 빌드에서 사용자 Minecraft 실플레이 정상 확인이 있었으며, 이는 **공개 Stable 파일과 다른 실행 파일**입니다. 기본 `main`은 아직 4.x 코드 기준입니다. 아래 10월 자료는 이력으로 보존합니다.

- [**GSC 5.0 최신 운영·유지보수·QA 구분 (2026-11-10)**](GSC-500-STATUS-2026-11-10.md)
- [GSC 5.0 유지보수 Draft PR #63](https://github.com/geumyi22/Geumyi-Minecraft-System/pull/63) — PC 로컬 적용 코드와 후속 검사 기록, 미병합

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
