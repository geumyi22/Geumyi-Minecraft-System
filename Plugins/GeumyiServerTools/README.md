# GeumyiServerTools 1.1.1 HOTFIX

Current runtime baseline: **GeumyiServerTools-1.1.1-SpigotPaper26.3-GSCv4.1-HOTFIX.jar**.

## Recovery status

The final 1.1.1 HOTFIX delta has been recovered and verified against the deployed HOTFIX binary.

- `GscRuntimeBridge`: `Bukkit.getMinecraftVersion()` -> `Bukkit.getBukkitVersion()`
- `HealthService`: same compatibility fix
- HOTFIX compatibility metadata recovered
- recovered overlay rebuild: **31/31 uncompressed JAR entries SHA-256 matched** the final HOTFIX

The older 0.1.5 core used underneath this overlay remains binary-only, so this is an **exact HOTFIX/overlay recovery**, not a claim of a complete original historical core source tree.

See:
- `HOTFIX-RECOVERY.md`
- `HOTFIX-PATCH.md`

Final binary remains in the `mc-2026.09.26-v3` Release.
