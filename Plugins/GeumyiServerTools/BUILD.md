# Build notes — GeumyiServerTools 1.1.1 HOTFIX

This remains an overlay/reconstruction build because the original complete 0.1.5 source tree is unavailable.

1. A preserved compatible core/reference JAR supplies classes that are not available as source.
2. The 1.1.x overlay sources provide GSC integration, maintenance, Diagnostics v2 and lag recording.
3. The current HOTFIX overlay includes the Spigot/Paper 26.3 compatibility change documented in `HOTFIX-RECOVERY.md`.
4. Bukkit stubs are compile-time only and are never packaged.
5. Overlay source and tests target Java 21 bytecode.
6. `build.sh` now compiles and executes `CoreTests` before packaging.

Local historical builds may use the preserved `base/GeumyiServerTools-0.1.5-Paper26.3.jar` when available.

Day-7 CI deliberately fetches the deployed 1.1.1 HOTFIX Release JAR as a verified binary core/reference and checks its pinned SHA-256 before rebuilding the source overlay. This does **not** turn the legacy binary-only core into recovered source and is documented as such.

The output name is:
`GeumyiServerTools-1.1.1-SpigotPaper26.3-GSCv4.1-HOTFIX.jar`
