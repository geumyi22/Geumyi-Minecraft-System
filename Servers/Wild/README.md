# Wild — Paper 26.3

The exact 2026-09-26 live operational configuration is **not fully recovered yet**.

Recovered evidence:
- current Paper 26.3 artifact provenance: `PAPER_26.3_INFO.json`
- sanitized 2026-09-10 operational `server.properties`: `server.properties.recovered-2026-09-10`
- that preserved config used Java port 25565 and RCON port 25575
- `accepts-transfers=true` was already enabled in that preserved config

The 2026-09-26 FINAL distribution contains Paper and managed plugin JARs but not the live `server.properties`, Paper/Spigot configs, plugin data folders, world data, or startup script. Therefore the recovered September 10 config is evidence only and is not promoted as the current live configuration.

All RCON/management secrets and historical resource-pack share URLs were removed before publication.

Expected current managed plugin set: GST 1.1.1 HOTFIX, GDS 1.1.1, Technology 0.1.3, Chemistry 0.4.1.

Distribution bundle remains in [Releases](https://github.com/geumyi22/Geumyi-Minecraft-System/releases/tag/mc-2026.09.26-v3).
