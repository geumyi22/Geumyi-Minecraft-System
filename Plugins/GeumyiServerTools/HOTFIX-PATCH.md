# Exact source delta: GST 1.1.1 -> 1.1.1 HOTFIX

```diff
--- pre-HOTFIX/src/main/java/kr/geumyi/servertools/GscRuntimeBridge.java
+++ HOTFIX/src/main/java/kr/geumyi/servertools/GscRuntimeBridge.java
@@
-                + "\"minecraft_version\":\"" + json(Bukkit.getMinecraftVersion()) + "\","
+                + "\"minecraft_version\":\"" + json(Bukkit.getBukkitVersion()) + "\","

--- pre-HOTFIX/src/main/java/kr/geumyi/servertools/HealthService.java
+++ HOTFIX/src/main/java/kr/geumyi/servertools/HealthService.java
@@
-        out.add(new Check("PASS", "Minecraft", Bukkit.getMinecraftVersion() + " / " + Bukkit.getVersion()));
+        out.add(new Check("PASS", "Minecraft", Bukkit.getBukkitVersion() + " / " + Bukkit.getVersion()));
```

HOTFIX metadata:

```properties
target=Spigot/Paper 26.3
version=0.1.5
compatibility=Spigot/Paper API 26.3
patches=Spigot compatibility hotfix: replaced Paper-only Bukkit.getMinecraftVersion() calls with Bukkit.getBukkitVersion()
```
