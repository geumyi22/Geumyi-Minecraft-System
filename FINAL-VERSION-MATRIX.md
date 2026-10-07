# FINAL Version Matrix

Status: **PENDING LIVE CAPTURE — Day 12 Phase 12.0A**

This file is the source/evidence side of the Golden Baseline. It does **not** mark Phase 12.0 complete until the real server-PC read-only capture is reviewed and a protected Golden Recovery Checkpoint is created in Phase 12.0B.

| Component | Frozen baseline | Evidence state |
|---|---|---|
| GSC | **4.3.8** | Day-11 Client/Host self-update + Final READ-ONLY E2E verified |
| GSCM | **1.1.5+117** | final two requested device checks user-confirmed PASS |
| GeumyiStatusAgent | **0.5.4** | recovered/CI baseline |
| GST | **1.1.1 HOTFIX** | recovered HOTFIX baseline |
| GDS | **1.1.1** | recovered/CI baseline |
| GeumyiTechnology | **0.1.4** | Wild + Other managed target |
| GeumyiChemistry | **0.4.1** | Wild + Other managed target |
| GeumyiNetwork | **0.1.0** | Day-10/11 routing baseline |
| GeumyiLobby | **0.1.0** | central Lobby baseline |
| Paper | **26.3** | Wild / Playground / Other / Lobby |

## Frozen release evidence

- Day-11 closure repository HEAD: `c96e02a17b8f4f527e1f630c1f9d5159fb47dab5`
- signed beta tag: `system-2026.10.07-day11-gsc438-beta`
- release target commit: `a17975030ed3f9b71d8632a7897c1c206d9bfcdf`
- Secure Release run: `37627140918`
- GSC 4.3.8 System CI: `37617403835`
- GSC CI artifact id: `11479763609`
- GSC CI artifact digest: `sha256:cab175afdd9a9b07e0d199dee9ff5ddf4383c216062ed8f2b12a7a528cb235cb`
- GSCM Android build117 CI: `37617292391`
- GSCM iOS build117 CI: `37617292404`

## Phase 12.0 completion boundary

12.0A must capture from the real server PC:

- GSC Host binary/config fingerprints;
- four server profiles and expected private ports;
- three Velocity/Geyser public entrypoints;
- managed plugin/proxy artifact fingerprints;
- fleet policy/update state;
- backup inventory/protection state;
- Windows service/startup tasks;
- disk headroom;
- no active unsafe transaction.

Then 12.0B must create and protect a dedicated Golden Recovery Checkpoint. Until both are done, this file remains **PENDING LIVE CAPTURE**.

Full local server paths, RCON passwords, API/device tokens, Floodgate private key contents and signing material are never committed to this public repository.
