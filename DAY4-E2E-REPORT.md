# Day 4 E2E verification — 2026-09-27

## Scope

Live Wild and Playground server operation was checked using the server-PC evidence bundle plus user-provided screenshots. Raw screenshots/log bundles are **not** committed because they contain local paths, network information and a live resource-pack share URL. Only sanitized derived evidence is stored here.

## Verified runtime state

- Host Java: **25.0.4.1 LTS**.
- Wild: **Paper 26.3**, 24 plugin JARs, normal boot to the running state.
- Playground: **Paper 26.3**, 24 plugin JARs, normal boot to the running state.
- GSC: **4.2.3**; Wild and Playground were both shown online.
- GSCM: **1.1.2**; realtime Control API connection active, Agent online, two managed Minecraft servers online.
- StatusAgent: **0.5.4** confirmed by Discord status output.
- GST: **1.1.1 HOTFIX** on both servers; collected `health-v2.json` reported `HEALTHY`, approximately 20 TPS and zero active lag incidents.
- GDS: **1.1.1** loaded on both servers; Discord status/heartbeat integration was observed.
- Discord notification flow showed an offline detection followed by connection recovery for Wild.
- Wild runtime JAR hashes for GST, GDS, GeumyiTechnology 0.1.3 and GeumyiChemistry 0.4.1 match the corresponding GitHub Release assets.
- Playground runtime JAR hashes for GST and GDS match the corresponding GitHub Release assets.
- Current live `server.properties` evidence was captured for both servers. Both have `accepts-transfers=true`, which remains relevant to the Day-10 Lobby/Transfer design.

## User-approved exclusions

These are intentionally **not** treated as Day-4 failures:

1. Bedrock/Geyser offline state and the Geyser enable error: currently tracked as a separate plugin compatibility issue.
2. The transient GSC `주의` state shown during server startup: treated as startup-transition behavior for this verification.
3. The third "Other" server being offline: it is outside the Wild/Playground Day-4 target.

## Non-blocking observations

- Playground AutoSaveWorld v4.15 logged 66 `Could not dump RegionFileCache` errors with `Can't find method saveLevel with params length 0` during the collected period. Surrounding AutoSaveWorld INFO messages continued through save/backup cycles, so this is recorded as a plugin compatibility follow-up rather than a Day-4 blocker.
- Both live server configurations currently have `resource-pack-sha1=` empty; Paper logs warn that clients may not refresh a pack unless its name changes.
- ProtocolLib warns that Minecraft/Paper 26.3 has not yet been tested by that installed build.
- DiscordSRV reports multiple missing configuration keys and falls back to defaults; no failure of the GDS/Agent status path was observed.

## Evidence-handling note

The collection tool successfully removed obvious token/private-key fields, but its first version did not redact a resource-pack URL written as an escaped `https\://` value and also split one keystore-password redaction awkwardly. Therefore the raw Day-4 evidence bundle is not publication-safe and is intentionally kept out of Git. The sanitized server-property snapshots in `Servers/Wild` and `Servers/Playground` are the canonical public evidence.

## Day-4 result

**Completed with documented exclusions and non-blocking follow-ups.**

No blocking fault was observed in the Java server, GSC, GSCM, StatusAgent, GST or GDS path. Bedrock/Geyser remains a separate known plugin issue and is excluded from this completion decision by user instruction.
