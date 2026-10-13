# Day12.10 — 실제 서버 Native Java/RCON 소유권·바인딩 관측 (2026-10-13 KST)

**실제 서버 제출 파일:** `DAY12-NATIVE-BIND-SHARE-ONLY-THIS.json`; 프라이빗 원본·PID·주소·계정·프로세스 명령행은 GitHub에 업로드하지 않음. 사용자 제출·검토 2026-10-13 22:58:56 KST (`captured_at=2026-10-13T13:58:56.1817278Z`). **`synthetic=false`, `read_only=true`.**

## 실제 관측 (정확한 증거 범위)

| 원본 JSON 필드 | 실제 값 |
|---|---|
| `phase` / `tool` | `12.10-live-online-native-bind-owner` / `DAY12_NATIVE_SCOPED_BACKEND_OWNER` |
| `result` | **`SCOPED_NATIVE_BIND_OWNER_REVIEW_REQUIRED`** |
| `online_backends_expected` | `wild`, `playground`, `lobby` (운영자/검사 설정상 기대값) |
| `other_backend_operator_expectation` | **`OFFLINE`** |
| `other_backend_actual_state_independently_verified` | **`false`** |
| `owner_paper_pairs_correlated` / expected | **3 / 3** |
| `scoped_online_private_port_count_observed` / expected | **6 / 6** |
| `unexpected_other_backend_listener_count` | **0** (Other 25572/25577, 조사 순간) |
| `reason_codes` | **빈 배열, 0건** |
| IPv4 `OWNER_PID_LISTENER` provider | `CAPTURED`; 매칭 행 **6** |
| IPv6 `OWNER_PID_LISTENER` provider | `CAPTURED`; 매칭 행 **0** |
| IPv4 `BASIC_LISTENER` provider | `CAPTURED`; 매칭 행 **6** |
| `network_adapter_firewall_acl_modified` | **`false`** |
| `services_processes_worlds_backups_modified` | **`false`** |
| `config_or_secrets_exported` | **`false`** |
| `other_server_started_by_tool` | **`false`** |
| `strict_backend_ports_private_gate` | **`UNCHANGED_FAIL_PENDING_RELEASE_REVIEW`** |
| `final_stable_release_allowed` | **`false`** |

## 전문가 검토 결론

**`PASS_SCOPED_LIVE_NATIVE_IPV4_LOOPBACK_PAPER_OWNER_6_OF_6`**: Windows Native `GetExtendedTcpTable`의 리스너 **전용** `OWNER_PID_LISTENER`와 `BASIC_LISTENER`를 활용해 실제 가동 대상이라고 **설정된** 세 Paper 인스턴스의 Java/RCON 6개 포트가 같은 Paper 역할 프로세스에 귀속되며, 관측된 주소가 루프백인 것을 *해당 시점에* 일치시켰다. Wild Java/RCON 25570/25575, Playground 25571/25576, Lobby 25573/25579의 총 **3쌍 모두 일치**. 프로세스 역할 매칭은 Java/Javaw 이미지와 Paper JAR 명령행 패턴을 사용하며, 실행 바이너리의 SHA나 전체 서비스 정책을 인증하지는 않는다. 과거 Windows build 26220에서 진짜 리스너가 raw TCP state **0**으로 보고된 현상을 반영해 **리스너 전용 API 테이블**에 대해서만 해당 상태를 수용했고 ALL 테이블 state0은 수용하지 않는다.

**IPv6 OWNER_PID provider가 `CAPTURED / matched 0`임은 수집 오류가 아니라 지정된 포트의 IPv6 리스너 매칭 행이 당시 없었다는 의미에 한정**된다. IPv6 비노출을 인터넷 전체 범위에서 인증하거나 IPv6 방화벽·다른 주소/네트워크 경로를 통과했다고 단정하지 않는다. **Other Paper는 운영자가 의도적으로 OFFLINE**, 해당 2개 포트의 이상 리스너 **0건**; 이를 Other 실실행 상태 검증 또는 가짜 8/8 온라인 PASS로 해석하지 않는다. Velocity 공개 프런트엔드 25567은 Other Paper와 별도다.

### 이번 증거로 끝나는 항목과 남는 항목

- **완료:** 이 순간 실서버 온라인 대상 **6/6 Java/RCON Native IPv4 루프백·소유 PID·Paper 역할** 스코프 확인. 기존 네트워크 LAN/Tailnet IPv4/IPv6 외부 접근 결과 `0/8`는 서로 다른 테스트 시점의 보조 방어 심층 증거다. 동일 TCP 리스너 진단을 반복 수행하지 않는다.
- **미완료:** 원본이 `SCOPED_NATIVE_BIND_OWNER_REVIEW_REQUIRED` 및 `strict_backend_ports_private_gate=UNCHANGED_FAIL_PENDING_RELEASE_REVIEW`라고 명시했으므로 12.10의 전체 네트워크 보안 게이트를 **자동 PASS로 변경하지 않는다**. Windows ActiveStore/WFP 실제 유효 규칙, 비루프백·IPv6·overlay 전체 위험 모델과 호스트 보안 12.5는 별도 검토 필요.
- **정식 배포:** `FINAL-RELEASE-GATES.json`의 `phase_12_10_backend_ports_private`는 아직 **FAIL**이며 `stable_release_allowed=false`. 최종 Stable 배포는 다른 실환경 필수 검증과 공식 정책 검토 완료 후에만 승인한다.
- **운영 영향:** 서버 시작·중단·업데이트, 기타 서버 기동, ACL·방화벽·월드·백업 수정 없음.

관련: [12.10 이전 Windows state0 실제 관측](../../reviews/DAY12-CLAUDE-V31-LIVE-STATE0-EVIDENCE-20261011.md), [12.10 보안 판단 기록](DAY12-PHASE10-BIND-DECISION-REPORT.md), [Day1~12 마스터](../../../PROJECT-DAY1-12-MASTER-STATUS-20261013.md), [최종 Stable 계획](../../DAY12-STABLE-FAST-TRACK-20261013.md).
