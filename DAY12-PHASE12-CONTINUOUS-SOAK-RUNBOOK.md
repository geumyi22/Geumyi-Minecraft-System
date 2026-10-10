# Day 12.12 — Eight-hour read-only continuous soak

**Purpose:** collect 8 hours of bounded server-PC evidence without disrupting any Minecraft world, GSC, Velocity, firewall, security settings or Golden backups.

Extract all files together on the actual **Minecraft server PC**. Run `Start_Day12_8H_Soak_READ_ONLY.cmd`, preferably when you do not anticipate any intended restart, update, reboot or network outage. Leave the console open for the full 8-hour run. The script makes a new timestamped `Desktop/Geumyi-Day12-Soak-YYYYMMDD-HHmmss/` directory and never overwrites prior evidence. It samples Java/GSC process identity and GSC-local Java TCP/Bedrock RakNet responses every 5 minutes.

When the command completes normally, upload **ONLY** `DAY12-SOAK-SUMMARY-SHARE-ONLY-THIS.json`. The `PRIVATE-SAMPLES-DO-NOT-UPLOAD.ndjson` contains local process IDs and remains on the server PC. An interrupted run has no final report; do not claim it finished.

**Limitations:** this is not a scheduled/background operating-system service or proof of actual Minecraft client sessions. Issues shorter than the sampling interval can be missed; it does not inspect logs or memory trends beyond observations, and unrelated Java processes can contribute to churn. Result is always `REVIEW_REQUIRED`; neither 8h passage nor the synthetic Windows CI grants production soak/Stable PASS. Separately review player experience, logs, CPU/RAM, backup/update behavior, and Day12.10 backend privacy proof before closeout.

The source has `-Synthetic` mode for Windows PowerShell 5.1 fail-closed unit tests. Only the actual server-PC run is observational evidence.

## Operator disposition update — 2026-10-11

The operator reports sustained uninterrupted usage without noticed issues and explicitly **accepts 12.12 operationally**. This optional telemetry kit should **not** be requested again as a routine prerequisite; it remains available solely if formal instrumented Stable evidence is later specifically needed. This acknowledgement is not the same as a timed 8-hour monitoring JSON or recorded CPU/RAM/process health. Refer to `DAY12-PHASE12-OPERATOR-SOAK-ACCEPTANCE-20261011.md`. The final release validator and strict live soak gate were deliberately not changed.
