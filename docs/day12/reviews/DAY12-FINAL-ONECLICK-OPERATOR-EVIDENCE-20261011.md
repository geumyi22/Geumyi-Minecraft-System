# Day12 Final OneClick — operator real-host report, 2026-10-11 KST

## Capture identity and scope

The operator uploaded `DAY12-FINAL-SHARE-ONLY-THIS.json` generated `2026-10-10T16:54:46Z` (2026-10-11 01:54:46 KST). JSON contract: `schema=1`, `report_type=GEUMYI_DAY12_FINAL_ONESHOT_READONLY`, `synthetic=false`, `checked_on_server_pc=true`, `result=CAPTURED_FOR_REVIEW_NOT_COMPLETE`.

This document records the **sanitized aggregate observations** from the submitted report. The operator's raw JSON is not copied to the public repository. No server, firewall, ACL, network, backup, cache or world mutation was reported.

| Phase | Observed real-host evidence | Boundaries |
|---|---|---|
| 12.5 GSC ACL | Five of five ACL targets found and readable; **3 potentially broad mutating allow ACEs** | ACE candidate count cannot prove effective rights of specific user/process token; no ACL changes |
| 12.5 Windows firewall | Two active profiles; three profile objects reviewed; 269 inbound rules (267 allow, 2 block); **38 enabled any-port+any-program candidate rules**; filter failures zero | This is a candidate inventory, not effective packet/WFP filtering proof or an instruction to disable any rules |
| 12.7 cache | Existing known-good cache manifest valid; **84/84** bytes SHA256+size match; missing/hash/size/invalid/duplicate/reparse zero | No offline boot executed |
| 12.7 startup preflight | Live GSC 4.3.8, zero jobs, Playground online and zero players, protected backup present | Explicit `BLOCKED_FOR_SAFETY` due to managed-updater policy; `MANAGED_UPDATER_NEEDS_APPROVAL`; network/service unchanged |
| 12.10 native TCP | Eight protected ports requested; **8 provider failures**, zero rows / zero owner PIDs; no observed wildcard/non-loopback rows | **Inconclusive**: zero observed rows when collection fails does *not* mean zero actual listeners, or exclusive loopback binding, or an externally reachable port. Formal gate remains `FAIL_UNVERIFIED_NATIVE_OWNER_ADDRESS` |
| 12.11 process census | GSC Host process 1; Java total 10; six Velocity candidates, three recognized Paper, **one unclassified Java**; 3/3 Geyser UDP ports each with one owner | Unknown Java role is not proof of a missing fourth Paper; no real crash, Canary apply or rollback was executed |

## Existing operator acceptance retained

Wild/Playground Java/Bedrock functional packs, all three Bedrock entry ports, Day12.4 no-op retention, Day12.12 ongoing trouble-free operation accepted as uninstrumented soak. Earlier LAN and tailnet IPv4/IPv6 four paths were bounded negative for protected TCP with public positive controls; selected unauthenticated GSC HTTP GETs returned 401 for 8/8. Do not repeat them without meaningful configuration changes.

## Narrow next actions — without unsanctioned production mutation

1. **12.10**: Diagnose **provider failure** using an independent, read-only collector that checks known-positive public listeners *in the same capture*; never treat missing private rows as PASS. Do not repeat unchanged failing Get-NetTCPConnection scans.
2. **12.11**: Classify the single unrecognized JVM by local process/port identity without exporting process command lines or private PIDs, and do not presume it is a fourth Paper solely from total Java count. An independently verified Java server/player-function report remains valid in its own scope.
3. **12.5**: Keep 38 broad firewall candidates and 3 ACL candidates as manual review items; confirm actual effective rule/ACE scope before proposing least-privilege changes with rollback.
4. **12.7**: Do not disconnect the network or restart production while managed updates are enabled. Use already passing disposable CI evidence for upstream-unavailable behavior and require an operator-approved, isolated staging design for strict real offline startup.
5. **12.11 #12/#17**: Real disposable crash-recovery was observed once in runner logs, but two CI workflows failed for harness reasons; no reproducible final green #12 suite or signed staging Canary rollback E2E. Do not kill production servers, invoke update apply or pretend the two strict cases are done.

**Release decision:** `FINAL-RELEASE-GATES.json` remains blocked; no Stable or maintenance promotion. Do not alter the 14 protected exact closed evidence IDs or bypass the release validator on this report. Operational 12.12 approval stays accepted without demanding a repeat soak.
