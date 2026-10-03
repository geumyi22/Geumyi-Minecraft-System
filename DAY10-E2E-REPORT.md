# Day 10 four-server host E2E report

Verification window: 2026-10-03 to 2026-10-04

## Scope

This report records what was actually exercised on the real server PC and what remains pending. User-run host checks are distinguished from CI/static checks.

## Exact source / CI baseline

- Exact recovery-safe source baseline used for the final cutover: `0e1490bfe75975eb278526df0f89a430109e28d8`
- Day10 Hotfix CI run `37113499045`: **SUCCESS**
- System CI run `37113499031`: **SUCCESS**

## Four-server topology

| Role | Public Java | Public Bedrock | Private Paper Java | RCON |
|---|---:|---:|---:|---:|
| Wild alias/backend | 25565 | 19132 | 25570 | 25575 |
| Playground alias/backend | 25566 | 19133 | 25571 | 25576 |
| Other alias/backend | 25567 | 19134 | 25572 | 25577 |
| Lobby | via all public aliases | via proxy layer | 25573 | 25579 |

Public Bedrock ports belong to Velocity/Geyser. GSC backend profiles use `bedrock_port=0`.

## Live cutover result

The final live run completed the following:

- full offline backups of Wild, Playground and Other;
- private backend port migration;
- Lobby creation/start;
- three isolated Velocity/Geyser/Floodgate instances;
- public TCP/UDP readiness checks;
- Java manual E2E confirmation;
- Bedrock manual E2E explicitly skipped as upstream-unsupported;
- durable Velocity startup tasks installed.

## Reboot verification

After a real Windows reboot, the user ran the reboot check and reported:

- `Geumyi Day10 Velocity wild` -> `Running`
- `Geumyi Day10 Velocity playground` -> `Running`
- `Geumyi Day10 Velocity other` -> `Running`
- TCP `25565`, `25566`, `25567` -> `LISTEN`
- UDP `19132`, `19133`, `19134` -> `BOUND`

## Real Java client E2E

The user then verified with a real Java client:

- public entry -> Lobby: **PASS**
- Lobby -> Wild: **PASS**
- Lobby -> Playground: **PASS**
- Lobby -> Other: **PASS**
- `/lobby`: **PASS**
- Wild last-position restoration: **PASS**
- Playground last-position restoration: **PASS**
- Other last-position restoration: **PASS**

Therefore the Java four-server cutover, routing and reboot-persistence scope is **PASS**.

## Recovery evidence

During Day 10 development, failed and interrupted cutovers exercised the rollback path. The final recovery-safe implementation preserves backups/quarantine, uses graceful Minecraft shutdown/RCON fallback, and only force-stops positively identified Day 10 proxy Java processes. An interrupted rollback was subsequently resumed and the user reported the final `INTERRUPTED DAY10 ROLLBACK VERIFIED` pass message before the successful final cutover.

## Bedrock status

Bedrock infrastructure listeners are present, but a real Bedrock client PASS is **not** claimed.

Current state: `SKIPPED_UPSTREAM_UNSUPPORTED`.

At the time of the host test, the latest Geyser available to the project did not yet support the current Bedrock client version. When upstream compatibility becomes available, run one real Bedrock client E2E covering Lobby entry, all three backend routes, `/lobby`, and last-position restoration.

## 2026-10-04 closure note

The upstream-compatibility statement above records the reason the original Bedrock test was skipped at the time of the host run. It is **historical evidence**, not a permanent closure condition.

If a newer Geyser build or supported-version notice is available, that alone does not change this report to PASS. Day 10 closes only after one real Bedrock client E2E verifies:

- public Bedrock entry -> Lobby;
- Lobby -> Wild / Playground / Other;
- `/lobby`;
- per-backend last-position restoration.

Until that is executed and observed, Bedrock remains **not verified**.

## Completion boundary

- Java four-server / Lobby / routing / reboot verification: **complete**.
- Bedrock real-client E2E: **pending actual client verification**. Upstream compatibility was the original skip reason, but a new build/support notice by itself is not a PASS.
- Full Day 10 closure should occur only after that Bedrock real-client E2E passes.
