# Build

Requirements: JDK 21+

```bash
bash build.sh
```

Output: `GeumyiDiscordStatus-1.1.1-SpigotPaper26.3.jar`

`stubs/` are compile-only Bukkit/Paper API stubs and must never be packaged into the JAR. `build.sh` checks this.
