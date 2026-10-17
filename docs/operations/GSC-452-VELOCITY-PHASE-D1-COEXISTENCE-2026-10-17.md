# GSC v4.5.2 Canary — Phase D1: disposable coexistence and read-only local IPC

**2026-10-17 — GitHub Draft PR #58. DEVELOPMENT EVIDENCE ONLY. NO RELEASE, MERGE OR PRODUCTION INSTALL.**

## Inputs and pinned public artifacts

The operator's sanitized `Velocity-Compatibility-READ-ONLY-20261017-224727.json` showed the same `velocity.jar` SHA-256 `35a5596a5468a035d8a32c8de5ebb0dc6b8d8f0cc3ff5169d514aca762af8aa8` across wild/playground/other; file size **42,163,652** and manifest hint **4.2.0**. All match PaperMC's official **Velocity 4.2.0 Build #30**, independently queried through https://fill.papermc.io/v3/projects/velocity/versions/4.2.0/builds. Host Java executable product-version hints were `26.0.2.0`, but the effective running-host JVM is **not attested**.

The temporary coexistence CI intentionally uses a **public, fixed, independently checksum-verified test stack**, not private JARs/plugins/configuration from the operator's server:

| Test input | Version/build | SHA-256 |
| --- | --- | --- |
| Velocity proxy | PaperMC 4.2.0 Build 30 | `35a5596a5468a035d8a32c8de5ebb0dc6b8d8f0cc3ff5169d514aca762af8aa8` |
| Geyser-Velocity | Geyser 2.12.0 Build 1263 (2026-10-17) | `f04cb787529b731ed5a1ab4797ee49bb5192c9ccec5217bfed2f368723036043` |
| Floodgate-Velocity | Floodgate 2.2.5 Build 141 (2026-09-17) | `649835022de37ff09255fc626d4bfe7bc2a3b926d07b0dfaf1f51e12bf37001d` |
| Geumyi Velocity Bridge | GSC 4.5.2 Canary **disabled prototype** | compiled from PR #58 source; **never installed on host** |

Official download API metadata: https://download.geysermc.org/v2/projects/geyser/versions/latest/builds/latest and https://download.geysermc.org/v2/projects/floodgate/versions/latest/builds/latest . The test itself uses the explicit project/version/build download URLs rather than a mutable `latest`.

## Disposable integration test (test runner ONLY)

Source: `tools/velocity/CI_Velocity420_Geyser_Floodgate_Smoke.py`, in the PR #58 workflow `.github/workflows/velocity-bridge-disabled-ci.yml`.

1. Download official pinned JARs into a new private temporary folder on the **GitHub-hosted runner**; reject mismatching SHA-256 or size, and apply download budgets.
2. Copy the CI-built no-op Geumyi plugin beside public Geyser and Floodgate JARs; **no copying from a real server**.
3. Launch the test proxy inside a disposable **Docker `--network none` container**, with all capabilities dropped, nonprivileged runner UID/GID, no privilege elevation, bounded process/memory/CPU resources, and **only that private temporary folder mounted**.
4. Check log markers for the three plugin IDs loading and the disabled Geumyi Bridge initialization. Raw log, generated Floodgate keys, working paths and player information are **not published**.
5. On timeout/error, fail closed; clean up **only the uniquely named CI-owned container and its temporary folder**. Any unsuccessful prerequisite is a blocker, not a fallback to real host.
6. This test is **plugin-initialization compatibility evidence only**, not a full Geyser/Floodgate functional handshake. With `--network none`, there can be no external backend, player or real Minecraft login and no real operational task-scheduler interaction.

The initial isolated CI attempt failed due to a test-runner bind-mount ownership mismatch (container process could not read the test JAR); matching the ephemeral runner UID/GID fixed this, without changing the user server or relaxing network isolation. The subsequent coexistence test passed.

## Read-only authenticated localhost IPC **fixture** (not deployed bridge)

Source: `tools/velocity/CI_Velocity_Localhost_ReadOnly_IPC.py`. It binds only to an ephemeral `127.0.0.1` TCP port on the CI runner, uses a random in-memory test-only HMAC-SHA256 key, and tests a Go/Java/Python shared canonical length-prefix envelope and `status` request.

- One authentic, unexpired scoped `status` succeeds with `read_only=true`, `safe_to_execute=false`.
- Reuse of nonce, forged MAC, wrong Velocity proxy, tampered process generation, expired envelope and unsupported lifecycle operation all reject.
- Every `prepare_shutdown`, `confirm_shutdown`, `start`, `stop`, `restart` and `kill` request rejects, including a correctly signed one.
- Only a fixed mock response is returned; **no actual GSC Host, Velocity plugin, process, task scheduler, Paper or world is connected**. There is no file-backed key, live token, privileged control route or production listener.

**IMPORTANT:** Although this demonstrates a local-only transport test and verifies compatible message signing, the *future* production IPC must still satisfy OS peer identity/ACL, per-proxy OS-protected key storage and rotation, request authorization tied to authenticated GSC operator session, key zeroization/replay persistence across restarts, rate limiting, player-count gate, operator maintenance window, audit trail, and exact task↔JVM identity. A random in-memory CI test key and localhost binding alone do not authenticate a real operator or a real Velocity process.

## Next gates before any release or live controls

- [x] SHA-256 attestation of operator-provided **Velocity 4.2.0 Build 30** JARs
- [x] Java bridge compile and tests against Velocity API 4.2.0 and 4.2.1-SNAPSHOT
- [x] Disposable bare proxy Java 25/26 plugin initialization smoke
- [x] Disposable **public** Geyser/Floodgate plus disabled bridge plugin co-loading (network-isolated)
- [x] One-shot signed localhost **read-only test fixture** (Go/Java/Python canonical vector); rejects all lifecycle verbs
- [ ] Verify the *actual operator-installed* Geyser/Floodgate builds via a separate privacy-preserving read-only inventory, if full production compatibility is needed
- [ ] Disposable Java+Bedrock **client E2E** with backend, credentials policy and resource-pack transfer
- [ ] Restricted authenticated production GSC↔Velocity **broker/plugin** design, independent security review and Windows OS peer identity ACLs (not implemented)
- [ ] Prove actual Day10 task-to-process ownership plus scheduler auto-restart semantics on disposable Windows VM
- [ ] Graceful zero-player shutdown in disposable VM (never `Stop-Process -Force` as normal stop), including negative player-present case and rollback
- [ ] Human approved maintenance window, GSCM compatibility/security gate, real in-game smoke and explicit `v4.5.2-canary` promotion

No source in this phase enables `ProxyServer.shutdown()`, live HTTP mutating API, control plugin socket, automatic server upgrade, or production start/stop/restart. **Leave PR #54, #55, #57, #58 Draft and unmerged; protect `main`, GSC v4.5.1 Stable, current Releases, proxy/Paper processes, worlds/backups/firewall/ACL.**
