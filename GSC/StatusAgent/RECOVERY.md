# StatusAgent helper-source recovery

Recovered 2026-09-27.

- `Codec.java`, `Json.java`, `MetricsLog.java`, and `MinecraftPing.java`: recovered from preserved earlier source and checked against the 0.5.4 deployed helper bytecode.
- `ServerState.java`: 0.4.5 adds exactly one field, `volatile int reportedJavaPort`, initialized to `0`; this delta was recovered from bytecode comparison.
- Core 0.5.4 files (`GeumyiStatusAgent.java`, `DiscordBot.java`, `GscClient.java`, `JsonOut.java`) come from the preserved 0.5.4 source package.

Validation against the preserved deployed 0.5.4 JAR:
- class/entry set: identical
- 12/17 JAR entries: byte-identical
- the five recompiled helper class entries (`Codec`, `Json` + parser, `MinecraftPing` + result) are not byte-identical to the historically overlaid class files, but normalized `javap -c -p -s` output matches after removing constant-pool indexes, instruction byte offsets and `ldc`/`ldc_w` encoding-width differences
- the deployed JAR remains the runtime baseline; the recovered tree is a full Java-source reconstruction, not a claim of a byte-for-byte reproducible historical build

This distinction matters because the original 0.5.4 artifact was assembled by overlaying new classes onto a preserved older binary base rather than recompiling every helper class in one clean build.
