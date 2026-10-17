# GSC v4.5.2 Canary — Velocity plugin compatibility / bridge Phase D0

**Status (2026-10-17): SOURCE-ONLY PROTOTYPE; NOT A RELEASE; NO DEPLOYMENT.**

## Target channel and version

- **GSC target:** `v4.5.2-canary`, a *planned* development label, not a published GitHub Release or installed binary. Do **not** rename 4.5.1 Stable or advance stable deployment manifests.
- **GSCM:** unchanged in this phase.
- **Velocity bridge experimental plugin version:** `0.1.0-canary-dev`, separate from GSC versioning.
- **Velocity API compile target (from official PaperMC 2026 docs):** `com.velocitypowered:velocity-api:4.2.1-SNAPSHOT`, JDK **25**. This is **not verified compatible with Geumyi's installed Velocity jars or Java runtime**.
- **No Java upgrade or Velocity upgrade** on the host, no plugin upload to any live plugins directory and no auto updater.

## Source implementation

`Plugins/GeumyiVelocityBridge`:

- `GeumyiVelocityBridge.java` registers only a Velocity plugin shell and emits a warning on initialization. It has **no socket/listener**, no command registration, no write channel, no scheduler creation, and never calls `ProxyServer.shutdown()`.
- `BridgeEnvelope.java` contains an **offline-only** Java port of the Go Phase C canonical HMAC-SHA256 envelope (see Draft PR #57), with 256-bit key minimum, target/action/generation scope, expiry and one-time nonce cache. The Java unit tests contain a fixed Go-compatible golden vector, tampering, expiry and concurrent replay checks. **No Velocity component invokes this verifier yet.** Successful authentication by itself would not constitute operator authorization.
- `.github/workflows/velocity-bridge-disabled-ci.yml` is a PR-gated isolated compile/test job. A successful build is **not** evidence that the production server uses the same JVM/API version or that a future bridge is safe to install.
- `tools/velocity/Velocity_Compatibility_READ_ONLY.ps1` can collect **sanitized** SHA-256 fingerprints, manifest version hints and executable product-version hints for UDP socket owners for the three expected Day10 task-associated `velocity.jar` files. It only reads JAR/task metadata and UDP socket owner Java executable file-version metadata in memory; paths and PIDs are not exported. Its default output is a JSON report on Desktop; it does not run Java, change processes/tasks, install any file or read forwarding secrets. A manifest or Java executable hint might be `UNKNOWN`, including on a valid runtime; an executable file-version hint does not prove the effective classloader/runtime JVM version. In all cases `runtime_api_compatibility_verified=false`.
- Windows CI exercises `-Synthetic` mode, not real operator tasks or private files.

## Evidence known before this phase

Earlier operator-supplied read-only JSON confirmed the wild/playground/other task configurations, three Velocity JVM parent/child pairs and three distinct UDP child process owners. Existing GSC UI independently reported successful Java TCP 25565,25566,25567 and Bedrock RakNet 19132,19133,19134 replies **6/6** on 2026-10-17. These are network-health observations, **not** proof of the runtime build/JDK version, individual scheduled task-to-process ownership, player E2E login or graceful shutdown.

## Why current production deployment is blocked

1. Actual installed three `velocity.jar` builds and Java majors must be collected read-only and compared to the dev API compile target. Manifest hints alone are not sufficient.
2. Plugin binary must pass isolated compatibility smoke on the **matching Velocity runtime build** in a disposable VM or container. Geyser/Floodgate, auth, Lobby, Java/Bedrock clients, and performance must not regress.
3. A future bridge needs per-instance OS-protected keys, authenticated loopback/named-pipe transport, local identity attestation, explicit operator approval, player-aware graceful shutdown, scheduler auto-restart interaction and no replay. The Stage C Go state machine must still be kept fail-closed.
4. A separate, operator-approved maintenance deployment/recovery plan is mandatory. Source CI green does not clear strict Stable gates.

**Forbidden for this proposal:** release publication, `main` merge, any live `velocity.jar` replacement, Paper/Velocity/GSC restart, auto `Canary` enrollment, change to worlds/backups/firewall/ACL, plugin installation or assumption of verified GSC v4.5.2 Stable.

Related: [PR #54](https://github.com/geumyi22/Geumyi-Minecraft-System/pull/54) (release channel policy); [PR #55](https://github.com/geumyi22/Geumyi-Minecraft-System/pull/55) (read-only status/preflight); [PR #57](https://github.com/geumyi22/Geumyi-Minecraft-System/pull/57) (offline simulator/HMAC); [Issue #56](https://github.com/geumyi22/Geumyi-Minecraft-System/issues/56) (full gated Velocity lifecycle).
