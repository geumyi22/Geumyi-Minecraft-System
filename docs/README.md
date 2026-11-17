# 금이 마인크래프트 시스템 문서 안내

> **기준: 2026-11-18** · 최신 공개 **개인용 GSC Stable 5.1.1**. `main`에는 4.x 복구 기반 소스가 있으며, 5.x 실행 코드는 각 공개 릴리스 태그로 구분합니다. PC 설치·실게임 QA와 GitHub CI 결과도 서로 구분합니다.

## 최신 릴리스와 현재 개발

- [**GMS / GSC 전체 GitHub 점검·정리 보고서 (2026-11-18)**](operations/GMS-GITHUB-AUDIT-2026-11-18.md) — 파일·PR·브랜치·릴리스 보존/삭제 판정
- [**GSC 5.1.1 최신 개인용 Stable: 기존 5.0 Host 이전 오류 수정**](operations/GSC-511-MIGRATION-HOTFIX-2026-11-15.md) — CI 21/21 성공, 실제 운영 PC 설치는 별도
- [GSC 5.1.2 개발 후보: Velocity 인증 콘솔·정상 종료/재시작 Issue #66](https://github.com/geumyi22/Geumyi-Minecraft-System/issues/66) — 아직 구현·E2E·Stable 미완료
- [GSC 5.1.0 릴리스 검증 (역사적)](operations/GSC-510-STABLE-2026-11-15.md) · [5.1 개발 전 CI 차단 기록](operations/GSC-510-DEVELOPMENT-STATUS-2026-11-15.md)
- [GSC 5.0.0 실플레이·유지보수 기록 (역사적)](operations/GSC-500-STATUS-2026-11-10.md)

## 공통 안내 및 이전 작업 이력

- [프로젝트 README](../README.md) · [운영 문서 목차](operations/INDEX.md) · [변경 기록](../CHANGELOG.md)
- [2026-10-24 이전 프로젝트 운영·PR 인수인계](operations/GMS-CURRENT-STATUS-2026-10-24.md)
- [2026-10-11 GSC 4.5.1/GSCM 1.5.1+151 이전 통합 릴리스](https://github.com/geumyi22/Geumyi-Minecraft-System/releases/tag/system-2026.10.11-stable-gsc451-gscm151)
- [Day 11 실기기 검증 체크리스트](operations/RELEASE-4.5.1-1.5.1-SMOKE-CHECKLIST.md) · [Day 1~12 현황](../DAY-TIMELINE.md)
- [프로젝트 과거 마감 보고서](../PROJECT-CLOSEOUT-2026-10-11.md) · [Day 4~11 기록](history/INDEX.md) · [Day 12 보고서](day12/INDEX.md)
- [공통 아키텍처·버전·복구·보안](reference/INDEX.md) · [기존 CI 워크플로 보관함](archive/workflows/README.md)

## 최상위 문서 보존 원칙

FINAL 게이트 JSON, 최종 E2E/버전 문서, Day 12 CI·Operator Kit가 루트에서 읽는 계획서·실행 안내, 소스 매니페스트는 위치를 변경하지 않았습니다.
이동은 Git 히스토리를 재작성하지 않으며 서버 파일·백업·실행 파일을 건드리지 않습니다.

## 코드에서 경로를 참조하여 이동하지 않은 문서

- DAY8-RUNBOOK.md — .github/workflows/system-ci.yml
- MAINTENANCE-MODE.md — .github/workflows/day12-final-gate.yml, .github/workflows/day12-final-release.yml
- VERSION-MATRIX.md — .github/workflows/day12-final-gate.yml, .github/workflows/day12-final-release.yml, .github/workflows/day12-operator-kit.yml
