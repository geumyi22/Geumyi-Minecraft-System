## 2026-10-11 00:42 KST — #2 Java process role discrepancy resolved, REAL HOST SCOPED PASS

The real `Day12-Unknown-Java-Role-READ-ONLY-20261011-004221.json` was uploaded and is **`PASS_SCOPED_ROLE_RECONCILIATION`**: six Velocity JVMs, three Paper JVMs, **one GeumyiStatusAgent**, zero unknown, and GSC snapshot exactly four known profiles with three ONLINE/one OFFLINE. Combined with the earlier six Velocity parent-child/three UDP owner evidence and GSC Host 1 Running, this **closes #2 within the scoped process census**. The old `REVIEW_REQUIRED` was caused by assuming all four profiles must have a running Paper process, and not recognizing StatusAgent. No process termination or server change.

The 18-item remainder status is **15 operator-accepted PASS/waived, 1 scoped real host PASS (#2), and 2 (#12/#17) disposable CI only / live E2E still OPEN**. This does not change 12.10 native bind FAIL, final 25-case gate or Stable release.
## 2026-10-11 — Combined #2/#12/#17 Safe CI PASS; only #2 real host census pending

[Workflow SUCCESS](https://github.com/geumyi22/Geumyi-Minecraft-System/actions/runs/38063619014) with ZIP artifact `Geumyi-Day12-Three-Remaining-OneClick-READ-ONLY`. The Windows PowerShell synthetic parser/topology and GSC Go recovery-state/dry-run/canary-policy/temp-file rollback tests passed. **#2 actual server-PC process census** still requires the operator to run the bundled **read-only CMD** and share one sanitized JSON. **#12 actual staged crash/recovery** and **#17 actual staged signed release apply/canary** were **not** performed by this test, so broader E2E gates remain OPEN. No dangerous production mutation is authorized.

# Day 12.11 — 18-item remainder operator PASS disposition (2026-10-11 KST)

This is **not** the canonical 25-case live E2E checklist, and it does **not** change the Stable release gate. It is an explicit record of the operator's requested statuses for the **18-entry outstanding-test numbered list** published immediately before their reply.

> Operator's selection: **1, 3, 4, 5, 6, 7, 8, 9, 10, 11, 13, 14, 15, 16, 18 패스 처리**

## Recorded user decision

- **15/18 selected:** `OPERATOR_ACCEPTED_PASS_TEST_WAIVED` → in the user-facing work tracker, acknowledge PASS by operator decision and **do not ask to repeat those routine cases**.
- **3/18 unselected:** **2 (duplicate/orphan process inventory), 12 (controlled unexpected-crash recovery in staging), 17 (update dry-run/canary/rollback)** remain OPEN.
- Prior already checked Java, Bedrock visual packs, GSC PC console polling, and GSCM Android console polling retain their distinct previously reported real-client PASS evidence.
- All 15 selected statuses are **operator acceptance**, not a statement that each operation was executed in this turn or that a log/artifact exists. Especially **1 Windows reboot, 9 device revoke/delete, 10–11 service stop, 14 scheduled action, 15 new backup, 16 restore** MUST NOT be represented as executed successfully without matching real evidence.
- The canonical 25-case `deploy/day12-final-live-e2e-checklist.json` remains unchanged; this new decision does not synthesize a 25-case form with 15 fabricated operator tests.

## Exact list-to-canonical-ID mapping

| # | Test | Work-tracker status | Canonical 12.11 ID |
|---:|---|---|---|
| 1 | 서버 PC 재부팅 → 자동 기동 | ✅ 운영자 PASS·추가 시험 생략 | `HOST_REBOOT_AND_AUTOSTART` |
| 2 | 중복·고아 프로세스 확인 | ⏳ 계속 미완료 | `HOST_NO_DUPLICATE_PROCESSES` |
| 3 | 베드락 3개 공개 포트 로비 진입 | ✅ 운영자 PASS·추가 시험 생략 | `BEDROCK_ALL_PUBLIC_ENTRIES_TO_LOBBY` |
| 4 | 베드락 로비↔3개 서버 이동 | ✅ 운영자 PASS·추가 시험 생략 | `BEDROCK_WILD_PLAYGROUND_OTHER_ROUTES` |
| 5 | 베드락 이전 위치 복원 | ✅ 운영자 PASS·추가 시험 생략 | `BEDROCK_LAST_LOCATIONS_RESTORED` |
| 6 | 베드락 Geyser 커스텀 아이템 매핑 | ✅ 운영자 PASS·추가 시험 생략 | `BEDROCK_WILD_GEYSER_ITEM_MAPPING` |
| 7 | GSCM Android 전체 상태·재연결·제어 | ✅ 운영자 PASS·추가 시험 생략 | `GSCM_ANDROID_STATUS_AND_CONTROL` |
| 8 | GSCM iOS 전체 상태·재연결·제어 | ✅ 운영자 PASS·추가 시험 생략 | `GSCM_IOS_STATUS_AND_CONTROL` |
| 9 | GSCM 기기 해제·삭제·재등록 | ✅ 운영자 PASS·추가 시험 생략 | `GSCM_DEVICE_REVOKE_DELETE_REPAIR` |
| 10 | GSC 서버 시작·중지·재시작 | ✅ 운영자 PASS·추가 시험 생략 | `GSC_CONTROLLED_START_STOP_RESTART` |
| 11 | 의도적 종료 → OFFLINE | ✅ 운영자 PASS·추가 시험 생략 | `GSC_INTENTIONAL_STOP_STAYS_OFFLINE` |
| 12 | 비정상 종료 → RECOVERING | ⏳ 계속 미완료 | `GSC_UNEXPECTED_LOSS_RECOVERING` |
| 13 | GSC 콘솔·RCON 제어 | ✅ 운영자 PASS·추가 시험 생략 | `GSC_CONSOLE_RCON_CONTROL` |
| 14 | GSC 예약 작업 실행 | ✅ 운영자 PASS·추가 시험 생략 | `GSC_SCHEDULE_EXECUTION` |
| 15 | 신규 백업 생성·검증 | ✅ 운영자 PASS·추가 시험 생략 | `GSC_NEW_BACKUP_AND_VERIFICATION` |
| 16 | 테스트 전용 서버 복원 | ✅ 운영자 PASS·추가 시험 생략 | `GSC_RESTORE_DISPOSABLE_ONLY` |
| 17 | 업데이트 Dry-run·Canary·Rollback | ⏳ 계속 미완료 | `GSC_UPDATE_DRYRUN_CANARY_ROLLBACK` |
| 18 | WebSocket 재연결·RCON 오탐 검증 | ✅ 운영자 PASS·추가 시험 생략 | `GSC_WS_RCON_RECONNECT` |

## Independent mandatory production gates (NOT waived by this list)

- **12.2:** component signed-release identity/hashes still need provenance review.
- **12.5:** Windows effective ACL/firewall rules still require security review.
- **12.7:** genuine offline known-good startup has not been run in an isolated real runtime.
- **12.10:** `backend_ports_private=FAIL_UNVERIFIED_NATIVE_OWNER_ADDRESS`; kernel process/port owner/bind evidence is incomplete, irrespective of useful LAN/Tailnet protection observations.
- **12.11:** full mandatory 25-case E2E evidence gate is not closed by the operator PASS/waiver request; cases 2, 12, 17 in this 18-item subset are explicitly left open.
- **12.12:** actual uninterrupted 8–12-hour stability soak has not been run.
- **12.13:** Stable/Maintenance promotion remains prohibited until mandatory requirements are satisfied.

Operational safety: no reboot, world restore, forced crash, service termination, backup mutation, firewall/ACL change, or Stable promotion is authorized by this **record-only** instruction.

Machine-readable companion: `deploy/day12-phase11-18-item-operator-disposition.json`. Both map numbers 1–18 to exact canonical test IDs to avoid confusing list number 1 with Day 12.1.

## 2026-10-11 00:29 — actual combined CMD result reviewed

The operator's one real ServerPC JSON reports **GSC 1 Running, Velocity 6 with 3/3 valid parent→child pairs and three owned UDP ports**, no duplicate PIDs among candidates, and **3 Paper-matching processes plus 1 other Java**. Because the lone JVM was not categorized by the strict Java `paper*.jar` matcher, **#2 is REVIEW_REQUIRED**; no broken server or orphan may be inferred from the count alone. The #12/#17 outcomes remain exact limited CI tests without a live crash/Canary. No server process was changed. The uploaded report is read-only and not committed. Full 25-case E2E, 12.10 backend bind evidence and Stable remain open.
