# Build notes — GeumyiServerTools 1.1.1 HOTFIX

This remains a reproducible overlay build because the original 0.1.5 complete source tree is unavailable.

1. `base/GeumyiServerTools-0.1.5-Paper26.3.jar` supplies the preserved core.
2. The 1.1.x overlay sources provide GSC integration, maintenance, Diagnostics v2 and lag recording.
3. The preserved core binary receives the same-length visible version constant replacement `0.1.5` -> `1.1.1`.
4. The current HOTFIX overlay includes the Spigot/Paper 26.3 compatibility change documented in `HOTFIX-RECOVERY.md`.
5. Bukkit stubs are compile-time only and are not packaged.
6. Overlay classes target Java 21 bytecode (class major 65), compatible with the deployed Java 25+/Paper 26.3 runtime.

The output name produced by `build.sh` is `GeumyiServerTools-1.1.1-SpigotPaper26.3-GSCv4.1-HOTFIX.jar`.
