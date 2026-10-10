# 금이 마인크래프트 시스템 — 최종 운영 안내

**2026-10-11:** Day 12는 소규모 운영 기준으로 마감됐습니다. 문제 없으면 현재 설치와 백업은 그대로 유지합니다.

- [최신 패키지 Stable — GSC 4.5.1 / GSCM 1.5.1+151](https://github.com/geumyi22/Geumyi-Minecraft-System/releases/tag/system-2026.10.11-stable-gsc451-gscm151)
- [프로젝트 종료·GitHub 정리 기록](../../PROJECT-CLOSEOUT-2026-10-11.md)
- [Day 1~12 완료 현황](../../DAY-TIMELINE.md)
- [Day 12 실운영·복구 절차](../../DAY12-LIVE-RUNBOOK.md)
- [정식 서명 Stable 보안 게이트](../../FINAL-RELEASE-GATES.json)
- [GSC 4.5.1 Ed25519 서명 Beta 업데이트](https://github.com/geumyi22/Geumyi-Minecraft-System/releases/tag/system-2026.10.11-gsc451-signed-beta.1) — 기존 Beta 공개키 동일·수동 설치 승인
- [PC 임시 파일 안전 청소](../../DAY1-12-PC-CLEANUP-GUIDE.md)
- [4.5.1/1.5.1 실기기 설치·회귀 테스트](RELEASE-4.5.1-1.5.1-SMOKE-CHECKLIST.md)

**유지보수 원칙:** 백업 확인 → 설치 파일 출처와 SHA-256 검증 → 한 대씩 설치 → Java·Bedrock·GSCM 확인 → 이상 시 롤백. 최신 GitHub 패키지는 수동 설치용이며 자동 배포되지 않았습니다. 마지막 실기기 확인 버전은 GSC 4.3.8/GSCM 1.1.5+117입니다. iOS IPA는 미서명입니다.
