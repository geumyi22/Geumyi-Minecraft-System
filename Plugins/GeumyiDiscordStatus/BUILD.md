# Build

Requirements: JDK 21+

```bash
bash build.sh
```

Output: `GeumyiDiscordStatus-1.1.1-SpigotPaper26.3.jar`

`build.sh` now:
1. compiles the Bukkit/Paper signature stubs,
2. compiles GDS with Java 21 bytecode,
3. compiles and runs `CoreTests`,
4. packages resources/classes,
5. rejects any JAR containing leaked `org/bukkit/` compile stubs,
6. checks JAR integrity.

The stubs are compile-only and must never be packaged into the JAR.
