# Build notes — GeumyiServerTools 1.1.0

This remains a reproducible overlay build because the original 0.1.5 complete source tree is unavailable.

1. `base/GeumyiServerTools-0.1.5-Paper26.3.jar` supplies the preserved core.
2. 1.1 overlay sources provide the GSC integration, maintenance, diagnostics v2 and lag recorder.
3. The preserved core binary receives only the same-length visible version constant replacement `0.1.5` -> `1.1.0`.
4. Bukkit stubs are compile-time only and are not packaged.
5. Overlay classes target Java 21 bytecode (class major 65), compatible with the user's Java 26 / Paper 26.3 runtime.
