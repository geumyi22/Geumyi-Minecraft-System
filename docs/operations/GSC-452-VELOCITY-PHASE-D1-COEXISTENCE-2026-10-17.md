# GSC v4.5.2 Canary — Phase D1: disposable coexistence and read-only local IPC

**2026-10-17 — GitHub Draft PR #58. DEVELOPMENT EVIDENCE ONLY. NO RELEASE, MERGE OR PRODUCTION INSTALL.**

## Inputs and pinned public artifacts

The operator's sanitized `Velocity-Compatibility-READ-ONLY-20261017-224727.json` showed the same `velocity.jar` SHA-256 `35a5596a5468a035d8a32c8de5ebb0dc6b8d8f0cc3ff5169d514aca762af8aa8` across wild/playground/other; file size **42,163,652** and manifest hint **4.2.0**. All match PaperMC's official **Velocity 4.2.0 Build #30**, independently queried through https://fill.papermc.io/v3/projects/velocity/versions/4.2.0/builds. Host Java executable product-version hints were `26.0.2.0`, but the effective running-host JVM is **not attested**.

The temporary coexistence CI intentionally uses a **public, fixed, independently checksum-verified test stack**, not private JARs/plugins/configuration from the operator's server:

| Test input | Version/build | SHA-256 |
| --- | --- | --- |
| Velocity proxy | PaperMC 4.2.0 Build 30 | `35a5596a5468a035d8a32c8de5ebb0dc6b8d8f0cc3ff5169d514aca762af8aa8` |
| Geyser-Velocity, **operator-matched** | **Geyser 2.11.3 Build 1251 (2026-10-10)** | **`dd963f2123704b89c47d3775b908b189b8174b1650008c51d37b1026d6dd928e`** |
| Geyser-Velocity, forward reference | Geyser 2.12.0 Build 1263 (2026-10-17) | `f04cb787529b731ed5a1ab4797ee49bb5192c9ccec5217bfed2f368723036043` |
| Floodgate-Velocity | Floodgate 2.2.5 Build 141 (2026-09-17) | `649835022de37ff09255fc626d4bfe7bc2a3b926d07b0dfaf1f51e12bf37001d` |
| Geumyi Velocity Bridge | GSC 4.5.2 Canary **disabled prototype** | compiled from PR #58 source; **never installed on host** |

**Operator-provided sanitized JAR fingerprint report** `GeyserFloodgate-READ-ONLY-20261018-000712.json` (collected 2026-10-18 00:07 KST): wild, playground and other each have one and only one recognized Geyser-Velocity JAR, SHA-256 `dd963f2123704b89c47d3775b908b189b8174b1650008c51d37b1026d6dd928e`, 48,674,589 bytes, and one Floodgate-Velocity JAR, SHA-256 `649835022de37ff09255fc626d4bfe7bc2a3b926d07b0dfaf1f51e12bf37001d`, 6,892,304 bytes. The source result says `actual_plugin_loading_verified=false`, `host_state_changed=false` and `jar_or_config_changed=false`. SHA-256 is an artifact identity comparison, **not verification that a particular JVM loaded that JAR or that Bedrock E2E works**.

**Official Geyser identity verified:** https://download.geysermc.org/v2/projects/geyser/versions/2.11.3/builds/1251 identifies exactly this Geyser SHA-256; the build was published at 2026-10-10T02:01:50Z. Existing Floodgate identity Build 141 and Velocity identity Build 30 were independently verified previously.

**Two independently named isolated cases** run against identical pinned Velocity and Floodgate artifacts: `operator` (real-server file-identity match, Geyser 2.11.3/1251, exact expected 48,674,589 bytes) and `reference` (newer Geyser 2.12.0/1263). CI must report both results. A success on the newer reference **must not be substituted** for an unsuccessful operator-matched case. Neither case installs anything on the operator's server.

Official fixed-version metadata: https://download.geysermc.org/v2/projects/geyser/versions/2.11.3/builds/1251 and https://download.geysermc.org/v2/projects/floodgate/versions/2.2.5/builds/141 . The tests never use mutable `latest` download URLs.

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

## Prepared operator Geyser/Floodgate inventory (not executed on real server)

Two adjacent files `tools/velocity/Run_GeyserFloodgate_READ_ONLY.cmd` and `tools/velocity/Velocity_GeyserFloodgate_READ_ONLY.ps1` inspect **only** `%ProgramData%\GeumyiServerCenter\Network\FourServer\{wild|playground|other}\plugins\*.jar`, matching exact `Geyser-Velocity[-suffix].jar` and `floodgate-velocity[-suffix].jar` names. The report contains only known proxy IDs, plugin-kind labels, candidate count, SHA-256 and JAR file size, with **no absolute paths, usernames, PID, Floodgate `key.pem`, YAML, secret or command line**.

Ambiguous duplicates and missing directories are classified as **loading unverified**, never as clean compatibility. The inspector does not look up Java classloaders, check server logs or load plugins; it cannot attest which JAR is currently running. It creates one sanitized JSON on the operator's Desktop and changes no server task/JAR/config. A Windows CI `-Synthetic` execution checks report shape and rejects duplicate/unrelated test names entirely in memory. GitHub Actions attaches the two-file kit as **`GSC452-GeyserFloodgate-READ-ONLY`** only after the job succeeds. The operator must share **only the sanitized JSON**.

## Operator-exact runtime smoke CI result (2026-10-18 KST)

Exact code+documentation head before this record was `c4011e95dda90440a4dc6faebca0f6691d557246`. GitHub Actions workflow `39044496861`, Velocity API 4.2.0 job `117430424981`, recorded BOTH of the following **separate PASS markers**:

- `profile=operator`: Velocity **4.2.0/30** + Geyser **2.11.3/1251** + Floodgate **2.2.5/141** + inert Geumyi bridge, with published file digest+expected byte size validated
- `profile=reference`: Velocity **4.2.0/30** + Geyser **2.12.0/1263** + Floodgate **2.2.5/141** + inert Geumyi bridge, with published hashes validated

The same workflow's Windows read-only fixture, local-only HMAC status IPC and API 4.2.1-SNAPSHOT tests were also green. Concurrent Day12 SBOM and Synthetic DR jobs passed. **This is a reproducible CI bootstrap observation, NOT live Bedrock Java login, resource pack handling, player auth, proxy-to-backend forwarding, maintenance or process lifecycle evidence.**

## Next gates before any release or live controls

- [x] SHA-256 attestation of operator-provided **Velocity 4.2.0 Build 30** JARs
- [x] Java bridge compile and tests against Velocity API 4.2.0 and 4.2.1-SNAPSHOT
- [x] Disposable bare proxy Java 25/26 plugin initialization smoke
- [x] Disposable **public** Geyser/Floodgate plus disabled bridge plugin co-loading (network-isolated)
- [x] One-shot signed localhost **read-only test fixture** (Go/Java/Python canonical vector); rejects all lifecycle verbs
- [x] Match all six inspected Geyser/Floodgate JAR hashes to official **Geyser 2.11.3 Build 1251 / Floodgate 2.2.5 Build 141** artifact identities (loaded runtime still unverified)
- [x] **Operator-matched Geyser 2.11.3 Build 1251** disposable SHA-pinned co-load smoke PASS; **newer reference Geyser 2.12.0 Build 1263** co-load smoke independently PASS (GitHub run `39044496861`, job `117430424981`, source commit `c4011e95dda90440a4dc6faebca0f6691d557246`)
- [ ] Disposable Java+Bedrock **client E2E** with backend, credentials policy and resource-pack transfer
- [ ] Restricted authenticated production GSC↔Velocity **broker/plugin** design, independent security review and Windows OS peer identity ACLs (not implemented)
- [ ] Prove actual Day10 task-to-process ownership plus scheduler auto-restart semantics on disposable Windows VM
- [ ] Graceful zero-player shutdown in disposable VM (never `Stop-Process -Force` as normal stop), including negative player-present case and rollback
- [ ] Human approved maintenance window, GSCM compatibility/security gate, real in-game smoke and explicit `v4.5.2-canary` promotion

No source in this phase enables `ProxyServer.shutdown()`, live HTTP mutating API, control plugin socket, automatic server upgrade, or production start/stop/restart. **Leave PR #54, #55, #57, #58 Draft and unmerged; protect `main`, GSC v4.5.1 Stable, current Releases, proxy/Paper processes, worlds/backups/firewall/ACL.**
