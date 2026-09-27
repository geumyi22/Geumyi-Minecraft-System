# StatusAgent helper-source recovery

Recovered 2026-09-27.

- `Codec.java`, `Json.java`, `MetricsLog.java`, and `MinecraftPing.java`: their compiled class bytes in 0.4.0 and the preserved 0.4.5 base JAR are identical.
- `ServerState.java`: 0.4.5 adds exactly one field, `volatile int reportedJavaPort`, initialized to `0`; this was recovered from bytecode comparison.
- Core 0.5.4 files (`GeumyiStatusAgent.java`, `DiscordBot.java`, `GscClient.java`, `JsonOut.java`) come from the preserved 0.5.4 source package.

Final validation compares every JAR entry against the preserved 0.5.4 release JAR. The recovered full-source build SHA-256 is `57bfa02211f733018c0174a9dc5d2ae9a2ede44d37aa838c33f56c3b51e3ce74`, identical to the preserved release JAR.
