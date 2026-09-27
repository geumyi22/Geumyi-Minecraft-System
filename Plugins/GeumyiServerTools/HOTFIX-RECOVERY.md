# GST 1.1.1 HOTFIX recovery

Recovered on 2026-09-27 from the preserved 1.1.1 overlay source and the final deployed HOTFIX JAR.

Verified HOTFIX delta relative to the pre-HOTFIX 1.1.1 build:
- `GscRuntimeBridge.java`: `Bukkit.getMinecraftVersion()` -> `Bukkit.getBukkitVersion()`
- `HealthService.java`: the same Spigot/Paper 26.3 compatibility change
- `META-INF/geumyi-26.3-upgrade.properties`: compatibility metadata

A recovered overlay rebuild was compared with the final HOTFIX using SHA-256 for every **uncompressed JAR entry**. All 31/31 entries matched. ZIP container SHA may differ because archive timestamps/order are separate metadata.

The unavailable legacy 0.1.5 core remains binary-only. This is therefore an exact HOTFIX/overlay recovery, not a claim that every historical core class was recovered as Java source.
