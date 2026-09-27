# GeumyiChemistry 0.4.1 source recovery

Reconstructed on 2026-09-27 from the preserved 0.4.0 source and the final 0.4.1 Paper 26.3 JAR.

Observed source/resource delta:
- plugin version 0.4.0 -> 0.4.1
- Paper API metadata 26.2 -> 26.3
- displayed version strings 0.4.0 -> 0.4.1
- `META-INF/geumyi-26.3-upgrade.properties` added

Validation:
- all final class files were compared against a clean rebuild
- method/field descriptors and bytecode operations match after normalizing constant-pool indexes, `ldc`/`ldc_w` encoding width, and instruction byte offsets
- `plugin.yml`, `config.yml`, and upgrade metadata match the final JAR byte-for-byte

The resource-pack generator/tools retain their preserved 0.4.0 content baseline because 0.4.1 is a server-plugin compatibility hotfix. The reconstruction is **not** claimed to be an untouched original 0.4.1 source package.
