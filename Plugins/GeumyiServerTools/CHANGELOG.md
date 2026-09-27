## 1.1.1 - Spigot/Paper 26.3 compatibility hotfix
- Replaced obsolete `org.bukkit.GameRules` linkage with Spigot 26.3 `GameRule`.
- Removed hard linkage to Paper-only TPS/MSPT and world count methods.
- Added reflective Paper metrics with scheduler/CPU-time fallback on Spigot.
- Uses standard `World#getLoadedChunks()` and `World#getEntities()` counters.

# Changelog

## 1.1.0
- Added Diagnostics v2 based on the existing core PerformanceMonitor samples.
- Added sustained TPS/MSPT/memory threshold incident detection and recovery tracking.
- Added `/gst diagnose` and `/gst lag`.
- Added `health-v2.json` and `lag-events.jsonl` runtime outputs.
- Upgraded runtime `status.json` and `capabilities.json` to schema 2 while retaining existing fields.
- Added session IDs to lag event records to avoid ambiguity after server restarts.
- Propagated diagnostics DEGRADED/CRITICAL state into the runtime health state.
- Extended the public service API using default methods for compatibility with 1.0 consumers.
- Preserved all 0.1.5 and 1.0.0 operational features.

## 1.0.0
- Promoted GeumyiServerTools from 0.1.x to a GSC v4-ready integration architecture.
- Added maintenance mode, safe-stop handshake, health self-test and local structured runtime telemetry.
