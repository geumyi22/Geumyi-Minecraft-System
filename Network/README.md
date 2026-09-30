# Day 10 Network / Velocity Foundation

This directory contains the staged network design for Day 10. It does **not**
modify the live Wild or Playground server by itself.

## Public entrypoints

- Java: Velocity on TCP 25565
- Bedrock: Geyser on Velocity on UDP 19132 (Phase 6)
- Every successful public login lands in Lobby first.

## Candidate internal backend ports

These ports are intentionally different from the current public server ports so
Velocity can own the public entrypoint without colliding with a backend.

| Role | Internal address |
|---|---|
| Lobby | 127.0.0.1:25569 |
| Wild | 127.0.0.1:25567 |
| Playground | 127.0.0.1:25568 |

RCON/GDS ports are not changed by this phase.

## Security rules

1. Velocity is the only Java listener exposed to players.
2. Paper backends bind to 127.0.0.1 after the migration is actually applied.
3. Velocity uses modern player information forwarding.
4. The forwarding secret is generated locally on the server PC and never
   committed to Git.
5. Backend Paper servers use online-mode=false only after modern forwarding and
   localhost/firewall protection are ready.
6. Existing Wild/Playground worlds are not copied, reset, regenerated or
   replaced.
7. The port cutover is not performed until Lobby and rollback paths are ready.

## Current compatibility decision

- Velocity is used as the proxy.
- Production staging resolves the latest non-SNAPSHOT stable Velocity build from
  PaperMC's official downloads service and records the selected version, build,
  URL and SHA-256 in a local lock file.
- Geyser is installed on Velocity, not separately on each backend.
- Floodgate is installed on Velocity. Backend Floodgate is only added later if
  a backend plugin needs the Floodgate API.
- Geyser currently emulates a Java 26.2 client. Because the current backends are
  Paper 26.3, Phase 6 must make the backend network accept 26.2 before Bedrock
  is declared PASS. The exact ViaVersion/ViaBackwards placement is verified
  against the then-current supported-version guidance before installation.

## Staging tool

`tools/day10/prepare_proxy_foundation.ps1` creates a non-destructive Velocity
staging directory containing:

- `velocity.toml`
- `forwarding.secret`
- `start.bat`
- `network-plan.json`
- optional pinned `velocity.jar` + SHA-256 lock information

The script does **not** edit Wild/Playground `server.properties`,
`paper-global.yml`, Windows Firewall, port forwarding, or router settings.

Those changes are applied only during the later controlled cutover after
preflight and backups.
