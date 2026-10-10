# 금이 마인크래프트 시스템 문서 안내

최상위 폴더의 복잡한 개발 기록을 일차별 및 주제별로 재배치했습니다.

## 찾아보기

- [현재 프로젝트 안내](../README.md)
- [최신 4.5.1/1.5.1+151 수동 설치 Stable](https://github.com/geumyi22/Geumyi-Minecraft-System/releases/tag/system-2026.10.11-stable-gsc451-gscm151)
- [실운영 기준 및 관리 자료](operations/INDEX.md)
- [4.5.1/1.5.1 실기기 검증 체크리스트](operations/RELEASE-4.5.1-1.5.1-SMOKE-CHECKLIST.md)
- [프로젝트 종료 보고서](../PROJECT-CLOSEOUT-2026-10-11.md)
- [Day 1~12 전체 일차 상태](../DAY-TIMELINE.md)
- [Day 4~11 이력](history/INDEX.md)
- [Day 12 상세 65개 보고서](day12/INDEX.md)
- [공통 아키텍처·버전·복구·보안](reference/INDEX.md)
- [운영 및 유지보수](operations/INDEX.md)
- [과거 CI 워크플로 보관함](archive/workflows/README.md)

## 최상위 문서 보존 원칙

FINAL 게이트 JSON, 최종 E2E/버전 문서, Day 12 CI·Operator Kit가 루트에서 읽는 계획서·실행 안내, 소스 매니페스트는 위치를 변경하지 않았습니다.
이동은 Git 히스토리를 재작성하지 않으며 서버 파일·백업·실행 파일을 건드리지 않습니다.

## 코드에서 경로를 참조하여 이동하지 않은 문서

- DAY8-RUNBOOK.md — .github/workflows/system-ci.yml
- MAINTENANCE-MODE.md — .github/workflows/day12-final-gate.yml, .github/workflows/day12-final-release.yml
- VERSION-MATRIX.md — .github/workflows/day12-final-gate.yml, .github/workflows/day12-final-release.yml, .github/workflows/day12-operator-kit.yml
