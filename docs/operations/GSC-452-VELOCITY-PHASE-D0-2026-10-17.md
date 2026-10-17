# GSC v4.5.2 Canary — Velocity plugin compatibility / bridge Phase D0

**Status (2026-10-17): SOURCE-ONLY PROTOTYPE; NOT A RELEASE; NO DEPLOYMENT.**

## Target channel and version

- **GSC target:** `v4.5.2-canary`, a *planned* development label, not a published GitHub Release or installed binary. Do **not** rename 4.5.1 Stable or advance stable deployment manifests.
- **GSCM:** unchanged in this phase.
- **Velocity bridge experimental plugin version:** `0.1.0-canary-dev`, separate from GSC versioning.
- **Velocity API compile baseline:** `com.velocitypowered:velocity-api:4.2.0` (corresponding to all three observed Velocity JAR manifest hints), JDK **25**. CI also compiles against the PaperMC documented `4.2.1-SNAPSHOT` as a forward-compatibility smoke. **Neither build proves compatibility with the actual running proxy processes.**
- **No Java upgrade or Velocity upgrade** on the host, no plugin upload to any live plugins directory and no auto updater.

## Source implementation

`Plugins/GeumyiVelocityBridge`:

- `GeumyiVelocityBridge.java` registers only a Velocity plugin shell and emits a warning on initialization. It has **no socket/listener**, no command registration, no write channel, no scheduler creation, and never calls `ProxyServer.shutdown()`.
- `BridgeEnvelope.java` contains an **offline-only** Java port of the Go Phase C canonical HMAC-SHA256 envelope (see Draft PR #57), with 256-bit key minimum, target/action/generation scope, expiry and one-time nonce cache. The Java unit tests contain a fixed Go-compatible golden vector, tampering, expiry and concurrent replay checks. **No Velocity component invokes this verifier yet.** Successful authentication by itself would not constitute operator authorization.
- `.github/workflows/velocity-bridge-disabled-ci.yml` is a PR-gated isolated compile/test job. A successful build is **not** evidence that the production server uses the same JVM/API version or that a future bridge is safe to install.
- `tools/velocity/Velocity_Compatibility_READ_ONLY.ps1` can collect **sanitized** SHA-256 fingerprints, manifest version hints and executable product-version hints for UDP socket owners for the three expected Day10 task-associated `velocity.jar` files. It only reads JAR/task metadata and UDP socket owner Java executable file-version metadata in memory; paths and PIDs are not exported. Its default output is a JSON report on Desktop; it does not run Java, change processes/tasks, install any file or read forwarding secrets. A manifest or Java executable hint might be `UNKNOWN`, including on a valid runtime; an executable file-version hint does not prove the effective classloader/runtime JVM version. In all cases `runtime_api_compatibility_verified=false`.
- Windows CI exercises `-Synthetic` mode, not real operator tasks or private files.
- Once CI is green, the Windows job attaches `GSC452-Velocity-Compatibility-READ-ONLY` containing exactly the CMD launcher and PS1 inspector. This is a **CI diagnostic kit**, not a release package or GSC v4.5.2 installer. Extract both files together, double-click the CMD only when an operator is ready to perform a read-only version check, and return only the sanitized Desktop JSON.

## 2026-10-17 22:47 KST — operator read-only artifact evidence

From the sanitized operator-supplied JSON `Velocity-Compatibility-READ-ONLY-20261017-224727.json`:

| ID | Day10 task present / JAR path expected | Velocity `MANIFEST.MF` version hint | Java executable product-version hint | SHA-256 of `velocity.jar` | Bytes |
| --- | --- | --- | --- | --- | ---: |
| wild | yes / yes | `4.2.0` | `26.0.2.0` | `35a5596a5468a035d8a32c8de5ebb0dc6b8d8f0cc3ff5169d514aca762af8aa8` | 42,163,652 |
| playground | yes / yes | `4.2.0` | `26.0.2.0` | same SHA-256 | 42,163,652 |
| other | yes / yes | `4.2.0` | `26.0.2.0` | same SHA-256 | 42,163,652 |

`host_state_changed=false`, `velocity_jar_or_config_changed=false`, **`runtime_api_compatibility_verified=false`**. These hints do not attest the current in-memory Java runtime major, runtime API linkage or whether the scheduled tasks own the specific Java executables. The observed equal SHA-256 proves the three inspected JAR files have the same SHA-256 value; it does **not** prove official build provenance or clean plugin compatibility. Do not publish the operator's private path or full host inventory.

Official public references: [Velocity 4.2.0 release](https://papermc.io/downloads/velocity), [Velocity API 4.2.0 Javadocs](https://jd.papermc.io/velocity/4.2.0/index.html), [current plugin development guide](https://docs.papermc.io/velocity/dev/creating-your-first-plugin/).

**New gate:** compile the disabled plugin source against 4.2.0 and 4.2.1-SNAPSHOT independently; use Java 25 toolchain to emit Java 25-compatible class files that Java 26 can nominally load. Actual matching-JAR runtime smoke on a disposable test proxy is still required, and **no production JAR or plugin should be installed, replaced or restarted**.

## Evidence known before this phase

Earlier operator-supplied read-only JSON confirmed the wild/playground/other task configurations, three Velocity JVM parent/child pairs and three distinct UDP child process owners. Existing GSC UI independently reported successful Java TCP 25565,25566,25567 and Bedrock RakNet 19132,19133,19134 replies **6/6** on 2026-10-17. These are network-health observations, **not** proof of the runtime build/JDK version, individual scheduled task-to-process ownership, player E2E login or graceful shutdown.

## Why current production deployment is blocked

1. Sanitized installed JAR and Java executable version hints have been collected; independently establish the effective running JVM major, official JAR provenance, bytecode linkage and actual API binary compatibility. Manifest/executable hints alone are insufficient.
2. Plugin binary must pass isolated compatibility smoke on the **matching Velocity runtime build** in a disposable VM or container. Geyser/Floodgate, auth, Lobby, Java/Bedrock clients, and performance must not regress.
3. A future bridge needs per-instance OS-protected keys, authenticated loopback/named-pipe transport, local identity attestation, explicit operator approval, player-aware graceful shutdown, scheduler auto-restart interaction and no replay. The Stage C Go state machine must still be kept fail-closed.
4. A separate, operator-approved maintenance deployment/recovery plan is mandatory. Source CI green does not clear strict Stable gates.

**Forbidden for this proposal:** release publication, `main` merge, any live `velocity.jar` replacement, Paper/Velocity/GSC restart, auto `Canary` enrollment, change to worlds/backups/firewall/ACL, plugin installation or assumption of verified GSC v4.5.2 Stable.

Related: [PR #54](https://github.com/geumyi22/Geumyi-Minecraft-System/pull/54) (release channel policy); [PR #55](https://github.com/geumyi22/Geumyi-Minecraft-System/pull/55) (read-only status/preflight); [PR #57](https://github.com/geumyi22/Geumyi-Minecraft-System/pull/57) (offline simulator/HMAC); [Issue #56](https://github.com/geumyi22/Geumyi-Minecraft-System/issues/56) (full gated Velocity lifecycle).
