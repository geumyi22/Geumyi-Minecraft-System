# FINAL Version Matrix

Status: **12.0A live READY + 12.0B Golden 4/4 PASS (operator evidence, 2026-10-09); 12.2 binary provenance still PENDING; Stable BLOCKED**

This matrix preserves the frozen Day-11 component targets and documents Day-12 real operator progress. Phase 12.0A baseline READY was recorded at 02:45 KST and **four of four protected full Golden checkpoints** PASS at 03:23 KST on 2026-10-09. This does NOT make the separate 12.2 component binary hash provenance or 12.10 native socket-owner security gates pass.

| Component | Frozen baseline | Evidence state |
|---|---|---|
| GSC | **4.3.8** | Day-11 Client/Host self-update + Final READ-ONLY E2E verified |
| GSCM | **1.1.5+117** | final two requested device checks user-confirmed PASS |
| GeumyiStatusAgent | **0.5.4** | 2026-10-10 09:59 real server: canonical filename present; **1** Java process command references expected filename; official artifact SHA-256 / loaded JAR identity **UNVERIFIED** |
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

## Phase 12.0 live evidence and unresolved completion boundary

The original 12.0A checklist required the real server PC to capture:

- GSC Host binary/config fingerprints;
- four server profiles and expected private ports;
- three Velocity/Geyser public entrypoints;
- managed plugin/proxy artifact fingerprints;
- fleet policy/update state;
- backup inventory/protection state;
- Windows service/startup tasks;
- disk headroom;
- no active unsafe transaction.

Operator evidence now records **12.0A READY** and **12.0B PASS with four protected Golden FULL archives**. Their actual archives remain on the Windows host and are not copied into GitHub. Any revalidation of the exact archives belongs to the operator, not CI. The frozen baseline evidence remains subject to **12.2 official artifact hashes**, **12.10 native socket ownership**, **12.11 real E2E**, **12.12 soak**, and separate signed Stable release gates. Do not recreate Golden archives or mark Stable PASS based on this document.

Full local server paths, RCON passwords, API/device tokens, Floodgate private key contents and signing material are never committed to this public repository.
