# Lobby backend

Day 10 adds **Lobby** as the central Paper backend behind Velocity.

## Purpose

- Every successful public Java login enters Lobby first.
- Lobby always places the player at the central spawn instead of restoring a Lobby position.
- Lobby provides routes to Wild, Playground and Other.
- `/lobby` returns backend players to Lobby.
- Wild/Playground/Other positions are stored separately and restored on return.
- Lobby is private behind Velocity and must not be exposed directly.

## Current local ports

- Java: `127.0.0.1:25573`
- RCON: `127.0.0.1:25579`
- GSC backend `bedrock_port`: `0`

## Runtime components

- Paper 26.3
- `GeumyiLobby-0.1.0.jar`
- Day 10 routing integration with `GeumyiNetwork-0.1.0.jar`
- Velocity modern forwarding secret generated locally during deployment

## Lobby map / selector

The current GeumyiLobby build uses a compact protected central plaza with three physical destination blocks:

- `EMERALD_BLOCK` -> Wild
- `DIAMOND_BLOCK` -> Playground
- `AMETHYST_BLOCK` -> Other

The compass selector is also available. The movement portal trigger is disabled by default in the current Day 10 baseline.

## Host verification

On the 2026-10-03/04 Day 10 host run, the user verified:

- public Java entry -> Lobby;
- Lobby -> Wild / Playground / Other;
- `/lobby` return;
- last-position restoration for all three backends;
- successful operation after a Windows reboot.

Bedrock client E2E remains pending upstream Geyser compatibility; no Bedrock PASS is claimed.
