# GeumyiTechnology 0.1.3 source recovery

Reconstructed on 2026-09-27 from the preserved 0.1.0 source, the preserved 0.1.2 compatibility JAR, and the final 0.1.3 Paper 26.3 JAR.

Verified source-level deltas:
- version 0.1.0 -> 0.1.3
- Paper API metadata 26.2 -> 26.3
- `Material.CHAIN` -> `Material.IRON_CHAIN` in both machine UI and `TechItem.POWER_CABLE`
- remaining descriptor changes such as `World.dropItemNaturally`, `Bukkit.getConsoleSender`, and `PlayerInventory.addItem` are Paper 26.3 API signature changes generated from the same Java logic

Validation:
- method/field descriptors and bytecode operations of the reconstructed classes match the deployed 0.1.3 JAR after normalizing constant-pool indexes, `ldc`/`ldc_w` encoding width, and instruction byte offsets
- deployed `plugin.yml`, `config.yml`, and `META-INF/geumyi-26.3-upgrade.properties` match byte-for-byte

The reconstruction is semantically matched to the deployed binary. It is **not** claimed to be an untouched original 0.1.3 source package or to reproduce identical class-file/ZIP bytes.
