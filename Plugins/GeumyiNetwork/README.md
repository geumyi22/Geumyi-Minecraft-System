# GeumyiNetwork 0.1.0

GeumyiNetwork provides the Day 10 cross-server routing/last-location integration used by the four-server topology.

## Responsibilities

- coordinate Lobby <-> backend transfer intent;
- keep last-position state separated by backend/server id;
- restore the last safe backend position when returning from Lobby;
- integrate backend movement availability with GSC network state.

## Verified scope

Real Java host E2E on 2026-10-03/04 confirmed routing and last-position restoration for Wild, Playground and Other. Bedrock real-client E2E remains pending upstream Geyser compatibility.

Do not interpret CI/static tests as a substitute for live client E2E.
