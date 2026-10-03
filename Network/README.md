# Day 10 Network / Velocity

This directory documents the **current four-server network topology** used by Day 10.
The historical single-proxy candidate layout is retired.

## Public entrypoints

| Alias | Java TCP | Bedrock UDP | First destination |
|---|---:|---:|---|
| Wild alias | 25565 | 19132 | Lobby |
| Playground alias | 25566 | 19133 | Lobby |
| Other alias | 25567 | 19134 | Lobby |

Three isolated Velocity processes own the public Java listeners. Each instance also carries Geyser/Floodgate for its matching UDP alias. All successful public sessions route to Lobby first.

## Private Paper backends

| Role | Internal Java | RCON |
|---|---:|---:|
| Wild | 127.0.0.1:25570 | 25575 |
| Playground | 127.0.0.1:25571 | 25576 |
| Other | 127.0.0.1:25572 | 25577 |
| Lobby | 127.0.0.1:25573 | 25579 |

GSC backend profiles use `bedrock_port=0`; public Bedrock UDP belongs to the proxy/Geyser layer, not to Paper backend profiles.

## Security and routing rules

1. Velocity is the public Java entry layer; Paper backends are private listeners.
2. Paper uses Velocity modern forwarding with a locally generated secret that is never committed to Git.
3. Floodgate identity material is generated/staged locally and shared only across the three Day 10 proxy instances.
4. External Java sessions always enter Lobby first.
5. Lobby -> Wild / Playground / Other restores the last safe position recorded for that backend.
6. `/lobby` returns the player to the central Lobby spawn.
7. Technology and Chemistry are targeted to Wild + Other, not Playground or Lobby.
8. Rollback never force-kills Minecraft backends; only positively identified Day 10 proxy Java processes may be forcibly stopped when required for recovery.

## Verified host status

On 2026-10-03, after a real Windows reboot:

- all three `Geumyi Day10 Velocity ...` scheduled tasks were `Running`;
- TCP 25565/25566/25567 were `LISTEN`;
- UDP 19132/19133/19134 were `BOUND`;
- a real Java client entered Lobby through the public endpoint;
- Lobby routing to Wild, Playground and Other worked;
- `/lobby` worked;
- last-position restoration worked for all three backends.

These are user-run host checks; they are not CI-simulated claims.

## Bedrock compatibility status

The UDP/Geyser infrastructure is present and bound, but the real Bedrock client E2E is currently `SKIPPED_UPSTREAM_UNSUPPORTED` because the latest Geyser available at the time of the host test does not yet support the current Bedrock client version. Do not label Bedrock as PASS until a real client test succeeds after upstream support is released.

## Staging and live tools

- `tools/day10/Day10_Phase1_Preflight.cmd`: read-only host inventory.
- `tools/day10/Day10_Phase2_Stage.cmd`: dependency staging and readiness validation.
- `tools/day10/Day10_FourServer_Live.cmd`: strict live launcher.
- `tools/day10/finish_four_servers.ps1`: four-server finalizer; supports explicit `-SkipBedrockManualE2E` for the temporary upstream-incompatibility case.
- `tools/day10/rollback_four_servers.ps1`: verified recovery path for failed/interrupted cutovers.

See `DAY10-PLAN.md` and `DAY10-E2E-REPORT.md` for completion boundaries.
