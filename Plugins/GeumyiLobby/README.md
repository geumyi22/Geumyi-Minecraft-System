# GeumyiLobby 0.1.0

GeumyiLobby provides the central Day 10 Lobby behavior behind Velocity.

## Current selector

- `EMERALD_BLOCK` -> Wild
- `DIAMOND_BLOCK` -> Playground
- `AMETHYST_BLOCK` -> Other
- compass selector is available
- Lobby join returns players to the central spawn
- movement portal triggering is disabled by default in the current baseline

## Protection / routing

The Lobby is intended as a lightweight protected hub rather than a normal survival world. Server requests are routed through the Day 10 network integration and are allowed only when the target is available.

## Verified scope

Real Java host E2E confirmed public entry -> Lobby, all three backend routes and `/lobby` after the final cutover and reboot. Bedrock real-client E2E is pending upstream Geyser compatibility.
