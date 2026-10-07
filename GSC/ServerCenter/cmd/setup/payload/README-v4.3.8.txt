Geumyi Server Center 4.3.8 — Day 11 Final / Day 12 Baseline

This package is the verified Day 11 GSC baseline and the starting point for Day 12 production hardening.

Verified Day 11 capabilities
- Client/Host split and separate self-update state.
- GSC Client and Host 4.3.7 -> 4.3.8 self-update paths user-confirmed live.
- Update Center fleet policy: managed/manual/hold, Stable/Beta/Canary, pin and dry-run.
- Player-aware scheduling and Canary rollout.
- Geyser/Floodgate/ViaVersion/ViaBackwards managed discovery/staging and guarded proxy apply.
- Protection & Recovery 2.0: provenance, protect/Trash/restore, permanent-delete confirmation gate, disk guard, retention dry-run, restore preflight/checkpoint/rollback.
- Registered-device revoke/restore/delete semantics.
- GSCM 1.1.5+117 coordinated baseline.

Safety
- Runtime/live PASS is never inferred from source or CI alone.
- Update/restore flows require verification, backup/checkpoint and health gates.
- Never expose RCON passwords, device tokens, Floodgate private keys or signing private keys.

Coordinated baseline
- GeumyiServerCenter 4.3.8
- GeumyiServerTools 1.1.1 HOTFIX
- GeumyiDiscordStatus 1.1.1
- GeumyiStatusAgent 0.5.4
- GSCM 1.1.5+117

Day 12
- Final Production Hardening & Closure starts from this baseline.
- FINAL-BASELINE.json and Day 12 verification tools define the final freeze/closure gates.
