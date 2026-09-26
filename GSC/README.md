# GSC 4.2.3 / StatusAgent 0.5.4

- [ServerCenter](ServerCenter/): recovered Go source, web UI, installer templates, tests and build script.
- [StatusAgent](StatusAgent/): recovered 0.5.4 compatibility-overlay source.

StatusAgent helper sources (Codec, Json, MetricsLog, MinecraftPing, ServerState) are **source not yet recovered**. The original build depends on the 0.4.5 base JAR; this binary is excluded from Git. Do not mistake the overlay for a complete source-only rebuild. See the component BUILD documents.
