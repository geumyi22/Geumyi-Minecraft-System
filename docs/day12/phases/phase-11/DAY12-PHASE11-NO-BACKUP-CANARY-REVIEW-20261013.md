# Day 12.11 — 서명 GSC 4.5.1 검증과 실제 Canary 롤백 경계 (2026-10-13)

**판정: `REPO_SIGNED_BETA_VERIFICATION_READY / LIVE_CANARY_APPLY_ROLLBACK_BLOCKED_NO_RECOVERY`**  
GitHub PR [#53](https://github.com/geumyi22/Geumyi-Minecraft-System/pull/53) Draft · 기타 Paper는 **의도적 OFFLINE** · 운영서버·월드·백업 변경 없음.

## 0. 2026-10-13 사용자 최신 운영상태 — 무엇이 달라졌나

- GSC **4.5.1 Host RUNNING**, Playground ONLINE·접속자 **0명**·Active Jobs **0건**이 실제 12.7 사전검사에서 관측됨. 현재 언제나 접속자 0명이라고 일반화할 수는 없음.
- **서버 파일 전체 백업들은 이전에 통과한 뒤 저장공간 때문에 운영자가 직접 모두 삭제했다고 확인함**. 과거 Golden 4/4의 내용은 그때 존재했거나 SHA 확인된 사실의 근거로만 남으며 **현재 이용 가능한 복구 체크포인트라고 볼 수 없음**. 다른 PC·드라이브·클라우드의 독립 복구본은 확인되지 않았음.
- 따라서 Playground/Wild/Lobby의 **실제 다운타임·자동업데이트 정책 전환·서명 Canary 적용·설치 실행·서비스 재시작·ACL/방화벽 변경을 유발하는 조작은 현재 BLOCKED**. 사용자가 전반적 진행을 승인했더라도 **실패 시 되돌릴 자료가 없다는 불변 조건**은 그대로 적용함. 저장공간이 부족한 상황에서 full world/server 백업을 자동으로 만들지 않음.
- 기존 8시간 실제 TCP·프로세스 연속 관측 97개 PASS, 실서버 Native IPv4 Java+RCON 소유 PID 3/3 Paper·6/6 포트 PASS, 기타 OFFLINE 범위, 이전 기능 E2E 수락은 재실행하지 않음.

## 1. 확인된 서명 릴리즈와 바로 사용하면 안 되는 오래된 초안

| 자료 | 확인된 상태 | 테스트에 사용할 수 있는 증거 범위 |
|---|---|---|
| [GSC 4.5.1 서명 Beta 공개 릴리즈](https://github.com/geumyi22/Geumyi-Minecraft-System/releases/tag/system-2026.10.11-gsc451-signed-beta.1) | `draft=false`, `prerelease=true`, **GSC Host/Client 4.5.1용** Ed25519 `deployment-beta.json`, 바이너리 SHA-256·서명 파일 공개 | **서명 검증과 정식 GSC 컴포넌트 범위**. Beta 채널이지 Canary나 새로운 Stable이 아님. 이미 4.5.1이라고 보고된 현재 서버에 같은 버전 self-update 적용 불가. |
| [GSC 4.5.1/GSCM 1.5.1+151 수동 Stable](https://github.com/geumyi22/Geumyi-Minecraft-System/releases/tag/system-2026.10.11-stable-gsc451-gscm151) | 공개, 이미 존재 | **다운로드 가능한 역사적 수동 설치 릴리즈**. PR #53 새 보안 패치를 포함하지 않음. |
| 2026-10-10 서명 `GSC 4.3.9-rc.1` Canary **GitHub Draft** | [2026-10-10 당시 기록](../phase-10/DAY12-PHASE10-GSC-4.3.9-RC1-SIGNED-CANARY-DRAFT-REPORT.md). 공개용 Canary와 현재 4.5.1보다 **낮은 버전** | 현재 4.5.1 호스트에 적용하면 **downgrade 차단**이 정상. 과거의 4.3.8 대상 설계를 최신 운영 호스트 테스트에 재사용하지 말 것. |
| [Day 12 현재 GSC 4.5.1 + Paper 26.3 격리 CI](https://github.com/geumyi22/Geumyi-Minecraft-System/actions/runs/38278642690) | 업데이트 출처 장애에서 실제 Paper 재기동, 별도 프로세스 강제 종료→watchdog `RECOVERING`→복구 성공 | **CI 러너의 실제 프로세스 E2E**. 운영자 서버의 온디스크 캐시/가동 상태/서명 Canary 배포·롤백 증거가 아님. |
| [새 공개 서명 Beta 검증 CI](https://github.com/geumyi22/Geumyi-Minecraft-System/actions/workflows/day12-gsc451-signed-beta-integrity-audit.yml) | 새 PR에서 추가된 공개자산/Ed25519 검증 workflow. **SUCCESS가 실제 기록된 후에만 PASS로 업데이트** | 정확한 매니페스트·설치 EXE 공개 SHA 및 서명 검증/변조 거부/정책 복원 단위 테스트. 이 테스트는 설치·재시작·롤백을 하지 않음. |

## 2. 실제 12.11 #17 서명 Canary 적용·롤백을 완료하려면

**디스포저블 PC/가상환경이 최선:** 프로덕션 서버와 **독립된 데이터·Windows 서비스·설치 디렉터리·인증 자산**을 이용하고, 다음 전제 조건을 모두 충족해야 함.

1. 사용 가능한 테스트 전용 호스트·스토리지 분리·원본 설치 파일 SHA256·복구 가능한 GSC-only 체크포인트·복원 명령 검증. **운영자 월드의 복제 또는 전체 백업이 필요하지 않도록 설계**. 단, GSC Client/Host 설정·Windows 서비스 원복 수단은 시험용으로 반드시 필요.
2. 테스트 환경에 **현재 4.5.1보다 새 버전으로 검증된** 서명 Canary를 생성해 전용 Canary 채널로만 노출. 별도 테스트 실행 파일 버전과 서명 공개키/매니페스트 `release`/파일 SHA256/릴리즈 태그가 일치해야 함. 기존 4.3.9 초안이나 같은 버전 4.5.1 Beta를 실제 업데이트 대상 버전으로 재사용하지 않음.
3. 시험 환경에서 설치 전 SHA256·원본 설정/키·GSC Host·Client 분리 역할을 확인. 서명 매니페스트 **실제 검증**, 스테이징, **시험용 설치** 후 Health PASS, 같은 호스트에서 의도적 **사전 계획된 실패** 삽입 → 원자적 롤백 → 원본 바이너리/설정 SHA 일치·서비스 Health·오류 코드 확인. 실제 운영서버 프로세스는 건드리지 않음.
4. 적용에 실패하거나 rollback 경로/서명·다운그레이드 제약이 불확실하면 즉시 중단하고 기록. 구현된 `canary_rollout.go` 정책 pin/restore의 Go 테스트는 **실제 Windows 설치 파일 교체와 원복 검증**과 구별.
5. 위 격리 시험 자체가 PASS여도 현재 운영 서버 4.5.1에 해당 PR 새 보안 코드가 배포됐다는 근거는 아님. 실 운영 최종 배포에는 별도 유효 복구 경로·엄격한 Day12 Security/Release gate가 필요.

## 3. Day 12.7·12.5·12.13 연동

- **12.7:** 사용자가 삭제 사실을 확인한 기존 전체 서버 백업을 다시 찾는 API 검사와 보호백업 PASS 조작은 중단. `AUTOMATIC_UPDATE_POLICY_MUST_BE_REVIEWED`도 해소되지 않은 실운영 가드. 실제 오프라인 기동은 **`BLOCKED_NO_RECOVERY_PATH`**, 현재 GSC4.5.1+Paper26.3 격리 장애시험만 범위 PASS.
- **12.5:** GSC 루트의 광범위 상속 WRITE 허용이 있던 Windows DACL은 아직 유효 표준사용자 거부가 증명되지 않음. 서버 PC에 별도 표준 계정이 없고, 관리자/UAC-filtered 토큰을 표준사용자로 대체하지 않음. **실효 보안 게이트 미검증**, ACL 변경과 백업 삭제를 혼동하지 않음. 최신 복구 경로 없이 ACL 권한 변경 안 함.
- **12.10:** 실제 운영 중인 3 Paper의 루프백 Java/RCON 6개 바인딩+PID 증명은 **범위 PASS**이나 Canonical WFP/전역 위험 평가는 별도.
- **12.12:** 실제 8시간·97샘플 TCP/프로세스 모니터 **범위 PASS**, 8시간 재검사 불필요.
- **12.13:** `FINAL-RELEASE-GATES.json`의 필수 값을 근거 없이 `PASS`로 바꾸지 않고, `stable_release_allowed=false`; **최종 자동 서명 Stable 미배포**, 기존 수동 Stable은 보존.

**다음 사용자 행동이 반드시 필요한 순간:** 실제 기기에 쓰기 작업이 필요한 경우 **검증 가능한 GSC-only 또는 서버 데이터 복원 방식과 사용할 테스트 장비가 확인된 후**. 지금은 대용량 백업이 삭제된 운영 서버에서 새로운 Canary를 실험할 이유가 없음.
