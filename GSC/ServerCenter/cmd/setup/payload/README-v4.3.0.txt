Geumyi Server Center 4.3.0 — Day 11 Operations UX & Fleet Management

This package is the Day 11 GSC target build.

Key source changes
- Update Center fleet policy: managed/manual/hold, per-server Stable/Beta/Canary channel and signed release pin.
- Player-aware update dry-run and scheduling safety.
- External Geyser/Floodgate/ViaVersion/ViaBackwards official-metadata discovery and SHA-256-gated staging.
- Signed GSC self-update discovery and verified staging.
- RCON health evidence bound to the current server lifetime.
- Protection & Recovery 2.0: protect/trash/restore/permanent delete, disk preflight and retention dry-run.
- Registered-device revoke/restore/delete semantics.
- GSCM 1.1.5 integration target.

Safety
- CI/build success is not live host E2E.
- External component staging does not claim live replacement.
- GSC self-update staging does not claim live helper replacement/relaunch rollback.
- Never expose RCON passwords, device tokens, Floodgate keys or signing private keys.

Coordinated target
- GeumyiServerCenter 4.3.0
- GeumyiServerTools 1.1.1 HOTFIX
- GeumyiDiscordStatus 1.1.1
- GeumyiStatusAgent 0.5.4
- GSCM 1.1.5+115
