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
3. Generate Geyser's *CI-only* default configuration using an ephemeral Docker `--network none` container. For an offline **unauthenticated RakNet PONG-only** check, require exactly one generated `validate-bedrock-login: true` field, change it to `false` **only in this disposable generated file**, then start the tested proxy on a unique Docker `--internal` network (no external route or published ports). Keep all capabilities dropped, nonprivileged runner UID/GID, bounded resources and **only the private temporary folder mounted**. This switch is NOT safe for any real server and cannot validate Xbox/player login or Floodgate authenticated gameplay.
4. Check plugin initialization markers; then **require a real Java server-list STATUS reply over TCP 25565 and RakNet unconnected PONG with echoed timestamp and magic over UDP 19132**, both from a fixed-loopback probe executed inside the same isolated test container. A plugin discovery marker alone is insufficient. Raw logs, generated Floodgate keys, working paths and any player information are **not published**.
5. On timeout/error, fail closed; clean up **only the uniquely named CI-owned container and its temporary folder**. Any unsuccessful prerequisite is a blocker, not a fallback to real host.
6. This test validates **plugin startup and two unauthenticated server-status protocols only**, not Java/Bedrock login, resource packs, proxy-to-backend forwarding, Floodgate authentication or a live Task Scheduler. The test container's unique `--internal` bridge allows its own loopback packets but has no external network routing or published ports; the operator's server is never involved.

The initial CI bind-mount ownership mismatch was corrected with the CI runner UID/GID. Later, a strict RakNet protocol check exposed a **test-only offline initialization prerequisite**: upstream `GeyserImpl.initialize()` calls `EncryptionUtils.getMojangPublicKey()` before `startInstance()` and returns early if that lookup fails while `validateBedrockLogin=true`. An isolated network cannot fetch that key. The workaround is scoped to an **unreachable, entirely temporary CI config and unauthenticated PONG-only test**. The real server's security controls and configuration are unchanged. Disabling Bedrock login validation on a reachable production proxy would be dangerous and is **strictly prohibited**.

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

## Strict Java STATUS + Bedrock RakNet PONG CI result (2026-10-18 KST)

Source head `4848d2e2d1707a680f621c2126af87041f45d11b`, workflow `39049747331`, Java 25/26 build job `117445726413` **PASS**. The logs independently contain the following markers for **each** of the two SHA-256-pinned profiles:

- `operator`: official Velocity 4.2.0/30 + exact operator Geyser 2.11.3/1251 + Floodgate 2.2.5/141 + inert Bridge; **Java STATUS TCP 25565 PASS** and **RakNet unconnected PONG UDP 19132 PASS**
- `reference`: official Velocity 4.2.0/30 + newer Geyser 2.12.0/1263 + Floodgate 2.2.5/141 + inert Bridge; **Java STATUS TCP 25565 PASS** and **RakNet unconnected PONG UDP 19132 PASS**

The initial UDP timeout was traced to **Mojang public-key startup dependency** in the deliberately offline sandbox; not to an on-host outage or an inherently incompatible Geyser/Velocity version. The Docker fixture generates and modifies only its own private Geyser config before launching a second disposable JVM with external networking disabled, no published ports and no player sessions. The generated Floodgate keys and raw config contents are not emitted. This test **cannot prove Bedrock authentication**, Java/Bedrock full E2E, connected players, backend forwarding, or compatibility with the operator's actual runtime config.

## Day10 Velocity Task Scheduler policy inventory — optional read-only operator step

CI-only inspector files `tools/velocity/Velocity_TaskPolicy_READ_ONLY.ps1` and `tools/velocity/Run_Velocity_TaskPolicy_READ_ONLY.cmd` provide the *next bounded operator diagnostic*, independent from any live restart/stop attempt. Its exact three allowed task names are `Geumyi Day10 Velocity wild`, `Geumyi Day10 Velocity playground`, and `Geumyi Day10 Velocity other`; only root-task (\) matches are considered. It reads task state, known action shape (without exporting paths or command lines), Windows Task Scheduler `RestartOnFailure.Count` and `MultipleInstancesPolicy` from in-memory exported XML. It emits only known target IDs, bounded task counts and allowlisted policy names, an explicit automatic-restart hazard classification, `task_to_jvm_identity_verified=false` and `live_control_authorized=false`. It does NOT write, stop, restart, unregister or alter a scheduled task, process, Java JAR, config, credentials, worlds or backups.

The main risk is a task configured to automatically relaunch a JVM after a graceful shutdown. A positive restart count is flagged `AUTO_RESTART_RISK_NO_GO`, while missing task policy or ambiguous action XML is `UNKNOWN_NO_GO`. **Even a task with zero automatic restarts is not permission to stop or restart the server.** Task definition metadata does not establish which PID is the active Task Scheduler instance or whether other watchdogs can start a JVM. Those proofs, a separate OS peer authentication design, zero-player confirmation and an explicit operator maintenance approval are still outstanding.

GitHub Actions only runs the script in `-Synthetic` mode to classify three fake high-restart-count tasks in memory, then attaches the two-file diagnostic kit `GSC452-Velocity-TaskPolicy-READ-ONLY`. The operator may run the CMD on the **server PC** when requested and share only the sanitized Desktop JSON; never share exported full task XML, configuration files, Java command lines or credentials. **This is a read-only policy inquiry, not a maintenance action or Canary deployment**.

## 2026-10-18 17:14 KST — real Task-JVM event report and diagnosis (NO-GO)

The operator shared ONLY `Velocity-TaskJvm-READ-ONLY-20261018-171400.json` with collector timestamp `2026-10-18T08:13:56.3062097+00:00` (17:13:56 KST). `synthetic=false`, `read_only=true`, `server_state_changed=false`, `task_state_modified=false`, `audit_log_settings_changed=false`, `source_authenticated=false`, `live_control_authorized=false`.

- Exactly three known Day10 scheduled tasks (wild, playground, other) each reported `task_running=true`.
- For all three, `task_event129_found=false`; therefore every event/PID/time/child/UDP *correlation field* remained false. Overall `EVENT_OR_PROCESS_CORRELATION_INCOMPLETE`.
- **This is missing evidence, not an observed Velocity outage, stopped JVM, unauthorized port ownership or proof of a broken Task Scheduler.** The earlier 3× Java TCP/Bedrock RakNet probes remain distinct prior observations; no new login or lifecycle probe was performed.
- The first collector swallowed all `Get-WinEvent` errors and could not distinguish a disabled Operational channel, no matching 129 record in its 48-hour window, query permission/failure, event overwrite, or a 1,200-record cap. **No one should reboot proxies, enable event logging, force a new task start or change the task's `RestartOnFailure.Count=999` merely to generate missing records.**
- This report is a *host-provided read-only observation*, not OS-authenticated proof of which scheduler instance owns which JVM. All 9 potential live start/stop/restart actions remain blocked.

### Collector hardening after the report (Draft PR #58 ONLY)

The next source revision stays read-only and preserves the report's existing `schema=1`, nine baseline safety booleans, the three fixed task IDs, and the top-level NO-GO result semantics. It adds a **sanitized** `event_log_state` (`ENABLED|DISABLED|UNAVAILABLE`), `event129_query_status` (`HAS_EVENTS|NO_MATCHES_48H|LOG_DISABLED|QUERY_FAILED|NOT_QUERIED`), fixed 48-hour window and scan-capped flag. This uses Microsoft's documented `Get-WinEvent -ListLog` read-only metadata API (https://learn.microsoft.com/en-us/powershell/module/microsoft.powershell.diagnostics/get-winevent?view=powershell-5.1), without `SaveChanges()` or channel settings changes.

If Task Scheduler event 129 is unavailable, it separately checks an **unauthenticated, event-independent liveness hint**: exactly one owned UDP endpoint for the known Bedrock port, one matching Java child process, one Java parent and consistent creation-time order. `udp_java_pair_hint=true` does NOT mean Task Scheduler owns that process and never sets `reliable_task_to_jvm_identity_verified` or `live_control_authorized`. All raw PIDs, event XML, task commands, JVM paths, user names and secrets stay out of JSON.

The Windows CI synthetic `-SyntheticCase NoEvent` must prove even an apparently healthy Java/UDP process hint cannot grant task attribution or lifecycle rights. **Do not request another server-PC run until the exact revised CI workflow passes and a new reviewed two-file artifact is produced.** All changes remain in Draft PR #58; no deployment, control endpoint, main merge, server changes or release promotion.

## 2026-10-18 17:59 KST — v2 operator read-only evidence: Event 129 channel DISABLED

Received `Velocity-TaskJvm-READ-ONLY-20261018-175904.json` (collected `2026-10-18T08:59:00.2951815Z`, 17:59 KST). Exact user-uploaded sanitized JSON, not a re-run or an OS-authenticated attestation:

| Target | Day10 task | TaskScheduler Operational | Event 129 | Independent UDP→Java child→Java parent hint | Task↔JVM identity | Live actions |
|---|---|---|---|---|---|---|
| wild | Running | DISABLED | Not available | true | unverified | blocked |
| playground | Running | DISABLED | Not available | true | unverified | blocked |
| other | Running | DISABLED | Not available | true | unverified | blocked |

Collector reported `event_log_state=DISABLED`, `event129_query_status=LOG_DISABLED`, `event129_window_hours=48`, `event129_scan_capped=false`, `result=EVENT_OR_PROCESS_CORRELATION_INCOMPLETE`, `synthetic=false`, `read_only=true`, and all mutation flags false. The 3/3 `udp_java_pair_hint=true` values show **event-independent read-only process-family consistency**, NOT task ownership, executable authenticity, correct client routing, authenticated remote controller identity, zero-player proof, or any authorization to stop/start/restart. `source_authenticated=false`, `reliable_task_to_jvm_identity_verified=false`, `live_control_authorized=false` stay fail-closed.

**NO operator log changes:** Never enable TaskScheduler Operational, clear logs, regenerate event 129 by restarting tasks, change `RestartOnFailure.Count=999`, elevate privileges, or stop JVMs to remove this warning. With the Operational channel disabled, an event-129-only correlation tool cannot close the evidence gap.

### Source-only D2 read-only Scheduler COM *engine* instance hint

To avoid another event-129 rerun loop, the draft adds `tools/velocity/Velocity_TaskInstance_COM_READ_ONLY.ps1` and adjacent CMD. It queries only three known registered task names via the local **read-only** Task Scheduler COM `Schedule.Service` → `GetFolder('\\')` → `GetTask(name)` → `GetInstances(0)` and retrieves `IRunningTask.EnginePID` from a unique visible instance. It compares the **engine PID** *in memory* against the Java parent/child associated with the expected Bedrock UDP port and emits sanitized categorical hints only, never raw PID/engine GUID/process paths/event XML/secrets. No calls to `Stop`, `Run`, `Register`, task settings APIs or event-log mutation are present.

**Important Microsoft API limitations:** `EnginePID` is the Task Scheduler *engine* process PID, **not guaranteed to equal the Java action process PID**. `IRegisteredTask::GetInstances(0)` may return no SYSTEM task instances to a less-privileged caller; invisible instances do not prove task absence. A matching PID is supporting evidence only and could be stale or incorrect if process generations race; a nonmatching engine PID is not proof the task is malfunctioning. Both cases yield `reliable_task_to_jvm_identity_verified=false`, `live_control_authorized=false` and `safe_to_start/stop/restart=false`.

Official references:
- Microsoft `IRegisteredTask::GetInstances`: https://learn.microsoft.com/en-us/windows/win32/api/taskschd/nf-taskschd-iregisteredtask-getinstances
- Microsoft `IRunningTask::get_EnginePID`: https://learn.microsoft.com/en-us/windows/win32/api/taskschd/nf-taskschd-irunningtask-get_enginepid
- Microsoft `RunningTask` properties: https://learn.microsoft.com/en-us/windows/win32/taskschd/runningtask

Windows CI runs **three in-memory synthetic cases** (positive engine-PID hint, no visible instances, multiple visible instances) and checks that all stay NO-GO. **The new live COM collector has not been run or validated on the operator's PC.** Only deliver the two-file kit after that branch's Windows CI succeeds. Do not install the disabled bridge plugin or unblock GSC controls, and do not merge to `main` without separate security review.

## Next gates before any release or live controls

- [x] SHA-256 attestation of operator-provided **Velocity 4.2.0 Build 30** JARs
- [x] Java bridge compile and tests against Velocity API 4.2.0 and 4.2.1-SNAPSHOT
- [x] Disposable bare proxy Java 25/26 plugin initialization smoke
- [x] Disposable **public** Geyser/Floodgate plus disabled bridge plugin co-loading (network-isolated)
- [x] One-shot signed localhost **read-only test fixture** (Go/Java/Python canonical vector); rejects all lifecycle verbs
- [x] Match all six inspected Geyser/Floodgate JAR hashes to official **Geyser 2.11.3 Build 1251 / Floodgate 2.2.5 Build 141** artifact identities (loaded runtime still unverified)
- [x] **Operator-matched Geyser 2.11.3 Build 1251** disposable SHA-pinned co-load smoke PASS; **newer reference Geyser 2.12.0 Build 1263** co-load smoke independently PASS (GitHub run `39044496861`, job `117430424981`, source commit `c4011e95dda90440a4dc6faebca0f6691d557246`)
- [x] Disposable operator-exact and reference profiles: **strict Java server-list STATUS + Bedrock RakNet unconnected PONG**, verified in CI with fixed loopback ports and test-only offline config
- [ ] Full Java+Bedrock **client login E2E** with backend, authenticated accounts, credentials policy and resource-pack transfer (not covered by status/ping)
- [ ] Restricted authenticated production GSC↔Velocity **broker/plugin** design, independent security review and Windows OS peer identity ACLs (not implemented)
- [ ] Prove actual Day10 task-to-process ownership plus scheduler auto-restart semantics on disposable Windows VM
- [ ] Graceful zero-player shutdown in disposable VM (never `Stop-Process -Force` as normal stop), including negative player-present case and rollback
- [ ] Human approved maintenance window, GSCM compatibility/security gate, real in-game smoke and explicit `v4.5.2-canary` promotion

No source in this phase enables `ProxyServer.shutdown()`, live HTTP mutating API, control plugin socket, automatic server upgrade, or production start/stop/restart. **Leave PR #54, #55, #57, #58 Draft and unmerged; protect `main`, GSC v4.5.1 Stable, current Releases, proxy/Paper processes, worlds/backups/firewall/ACL.**

## 2026-10-18 18:20 KST — COM Task instance observation (live READ ONLY)

The operator ran the approved Task Scheduler COM read-only kit on the real Windows server PC and shared only `Velocity-TaskInstance-COM-READ-ONLY-20261018-182023.json` (collected `2026-10-18T09:20:18.9662913Z`). The result is `TASK_INSTANCE_HINTS_UNVERIFIED_NO_GO`. `synthetic=false`, `read_only=true`, `source_authenticated=false`, `live_control_authorized=false`, and all server/task/event-log mutation and elevation flags are false.

| Proxy | Task state | Visible task instances | Engine PID present/visible | Engine PID = Java parent | Independent UDP→child→parent hint | Trusted process control |
|---|---|---:|---|---|---|---|
| wild | Running | 1 | yes/yes | true | true | **NO-GO** |
| playground | Running | 1 | yes/yes | true | true | **NO-GO** |
| other | Running | 1 | yes/yes | true | true | **NO-GO** |

All three reported `engine_pid_matches_udp_java_child=false`, consistent with the engine PID matching the Java parent instead of the child. All three report `reliable_task_to_jvm_identity_verified=false`, `safe_to_start=false`, `safe_to_stop=false`, `safe_to_restart=false`.

**Interpretation:** unusually strong **concurrent process association hints** across all three known tasks, but not an independently authenticated task-to-JVM identity, not a way to prove the process will remain the same between observation and any future action, and not an actual Java+Bedrock login E2E. The Task Scheduler Operational channel remains disabled per the earlier report; this COM check succeeded without changing it. Do not ask the operator to repeat these collectors simply to make a status label change. Keep the Day10 `RestartOnFailure.Count=999` policy intact.

**Next source-only work:** review these exact sanitized fields against fail-closed pure Go classification in Draft PR #57; independently test no-player gating, OS peer authorization, safe maintenance restore and synthetic negative cases before any real GSC control integration. No operator live maintenance is authorized by the COM result.


## 2026-10-18 — Principal-scope read-only readiness for DACL/DPAPI design

After the real 18:20 KST Task Scheduler COM report confirmed a **single visible running instance per target**, an EnginePID equal to each Java parent and a consistent UDP-owner Java child (still `source_authenticated=false` / NO-GO), source-only isolation in Draft PR #57 added Windows process HANDLE/generation checks, live Win32 named-pipe interprocess tests, exact-SID DACL construction, short-lived HMAC challenges and **Windows user-scope DPAPI-only** per-proxy key guards. This is not deployment.

**Essential remaining operator-specific fact:** do the three actual Day10 scheduled-task principals, the Java parent/child processes, and the *interactive diagnostic user* share the same Windows SID? If accounts differ, the named-pipe ACL and HMAC secret distribution must be explicitly designed for multiple independently authenticated principals. It would be unsafe to assume that the CLI user's Windows current-user DPAPI credential can be used by GSC's runtime or Java task accounts.

The optional `tools/velocity/Velocity_PrincipalScope_READ_ONLY.ps1` + adjacent CMD makes exactly that narrowly scoped **read-only relationship check** on the server PC. It examines only the three fixed known task principals, three expected UDP Java process families, their process-owner SID through `Win32_Process.GetOwnerSid`, and the collector's own Windows identity. It outputs only per-proxy `MATCH|DIFFERENT|UNKNOWN`, observed task-running state and category booleans. No raw usernames, SIDs, PIDs, process command lines, Java paths, task XML, secrets, DPAPI keys or access tokens are written. All live authorization flags stay false even if all comparisons match. `-Synthetic` is the ONLY mode used by CI.

**Caveat:** the collector user's account is not necessarily the **GSC host process** account. The report cannot authenticate GSC's running service or prove that either process can decrypt a future HMAC key. A `DIFFERENT` is a scoping/design input, not an outage or automatic repair condition. If CIM owner queries lack permission, report `UNKNOWN` without elevation. Do NOT rerun earlier event collectors, enable Task Scheduler Operational, restart JVMs, alter task policy or request raw SID screenshots.

Provide only the sanitized `Velocity-PrincipalScope-READ-ONLY-*.json` after the new **Windows CI synthetic validation** passes; until then keep the kit source-only. The eventual Canary deployment remains separately gated by genuine Java-side plugin authentication, player-free admission fencing, bounded policy restoration, disposable VM exit/retry semantics and explicit operator approval. **NO-GO** on all real lifecycle actions.


## 2026-10-19 02:09 KST — real Windows principal relationships (NO-GO)

The operator executed the read-only principal-scope collector and shared **sanitized** `Velocity-PrincipalScope-READ-ONLY-20261019-020937.json` (UTC timestamp `2026-10-18T17:09:32.5056097+00:00`). The reported result is `THREE_PRINCIPAL_RELATIONSHIPS_CAPTURED_NOT_AUTHORIZED`, `synthetic=false`, `read_only=true`, `source_authenticated=false`, `live_control_authorized=false`; all task/server/ACL/audit-log mutation, DPAPI-access and elevation flags are false.

| Target | Task Running | Task↔Java owner SID | Java parent↔child owner SID | Task↔interactive collector SID | Java↔interactive collector SID | Runtime task/JVM identity | DPAPI cross-principal compatibility |
|---|---|---|---|---|---|---|---|
| wild | yes | MATCH | MATCH | DIFFERENT | DIFFERENT | unverified | unverified |
| playground | yes | MATCH | MATCH | DIFFERENT | DIFFERENT | unverified | unverified |
| other | yes | MATCH | MATCH | DIFFERENT | DIFFERENT | unverified | unverified |

**Consequences:** all three known Day10 Java parents and UDP-owning Java children report the same account as their respective scheduled task, but all differ from the *interactive diagnostic collector*. Do NOT assume GSC host executable itself runs as the collector account; this report does not inspect GSC's running process. Do NOT attempt to decrypt an interactive user's `dpapi-u:` blob under the task/Velocity account, silently fall back to `dpapi-m:` or plaintext, modify task security settings, impersonate another account, or request protected material. The current user-scope DPAPI key helpers in Draft PR #57 are **source-only single-principal primitives**, not a cross-principal distribution solution.

**Decision: separate GSC runtime account identity, actual Velocity account identity and an explicit owner-verified per-proxy secret custody plan.** Prefer OS ACL-protected local named-pipe access and fresh process/creation-time attestation, with bounded challenge messages. Before any live use, the installed running GSC service's own SID must be independently authenticated (not inferred from an operator CMD window); a verified JVM/plugin key provision or an OS-authenticated, reviewable alternative must be designed and tested in disposable Windows environments. There is no authorized production stop/start/restart pathway.

### Offline admission gate progress

`Plugins/GeumyiVelocityBridge/src/main/java/kr/geumyi/velocitybridge/AdmissionFence.java` adds a **nonwired** admission-freeze and in-flight/unpublished-login model. It is not a registered Velocity event listener, performs zero plugin commands and never calls `ProxyServer.shutdown()`. JUnit tests simulate queued login, completed-but-not-published connection, zero online sessions, generation replay/cancellation and concurrent freeze; even a successful in-memory drain shape cannot authorize live stop. A real plugin must integrate with Velocity's supported login and disconnect events, independently authenticate the local GSC broker, drain already admitted players and atomically guard late arrivals before shutdown. This is a compatibility and concurrency modeling step only.

**Next gates:** PR #57's strict read-only JSON review and negative tests; PR #58's Java admission model and Velocity API compilation; independent cross-principal IPC architecture and key custody; isolated Windows task and JVM lifecycle correctness under restart policy 999, plugin real player-free shutdown and actual Java/Bedrock login E2E. Preserve both Drafts and `main`.


## 2026-10-19 — final scoped GSC host-vs-task account observation

The real `Velocity-PrincipalScope-READ-ONLY-20261019-020937.json` conclusively **reported** (but did not independently authenticate) that the three Day10 task accounts and their Java parent/child accounts match **within each proxy**, while each differs from the **interactive collector account**. Nothing in that report determines the actual `GeumyiServerHost.exe` process account; it may be identical to either principal or a third account.

To resolve the one remaining account-topology input without another speculative PID/log loop, the Draft source adds `tools/velocity/Velocity_GSC_HostPrincipal_READ_ONLY.ps1` and adjacent CMD. `GSC/ServerCenter/build.ps1` confirms the actual binary basename `GeumyiServerHost.exe` (distinct from the `GeumyiServerCenter.exe` interactive client), so the collector restricts WMI query to **exactly that basename** and checks whether exactly one instance is visible. It then compares the host owner's Windows SID in memory with the three **fixed scheduled task** principal SIDs, and separately compares the host owner with the current interactive collector. Output includes only `MATCH|DIFFERENT|UNKNOWN`, `NONE|ONE|MULTIPLE|UNKNOWN`, task-running booleans and permanent NO-GO guards.

**Hard limits:** A matched process basename and account SID do not attest the executable hash, the actual GSC application code running within it, or the Java plugin/transport owner. Even a match does NOT prove a DPAPI blob can be decrypted by both principals, confer stop/restart permissions, or grant authority. No plaintext, DPAPI, task XML, usernames, SIDs, PIDs, Java paths, command lines or secrets are read into the report. No ACL, task, event-log, credential, running process, server or backup change is made. The tool never elevates privileges; if no host, multiple hosts or access denied, output is `UNKNOWN` and must **not** be "fixed" by starting/restarting a service.

The Windows CI tests `HostDifferent`, `HostSame`, `NoHost`, `MultipleHosts` entirely synthetically and attaches the two-file `GSC452-HostPrincipal-READ-ONLY` ZIP. Only after all workflow jobs succeed may the user run this **single final host-account observation**. Its value is an architecture input for a future OS-account-scoped named-pipe broker, not a release acceptance gate. Keep all live lifecycle routes disabled.

Meanwhile:
- Draft PR #57 validates the **real-shape** principal report strictly, explicitly rejects forged account/DPAPI authorization, and merges only the three historical sanitized reports as a NO-GO status summary.
- Draft PR #58 adds the **unwired Java admission fence**, with blocking of pending and committed-but-unpublished logins before any theoretical player-count-zero decision; Velocity 4.2.0 and 4.2.1-SNAPSHOT compilation is tested on CI.
- Never bypass player fencing, scheduler 999 failure semantics, GSC runtime process integrity, JVM generation, operator approval or actual Java/Bedrock login E2E by treating these readonly hints as valid shutdown authentication.

## 2026-10-19 02:33 KST — same-principal topology and real Java 25 Win32 pipe feasibility

Sanitized `Velocity-GSC-HostPrincipal-READ-ONLY-20261019-023357.json` reports **exactly ONE** `GeumyiServerHost.exe` process by basename, the *same account SID* as the three Day10 scheduled-task principals, and a *different SID* from the interactive diagnostic account. Combined with the preceding PrincipalScope report, this suggests one GSC/proxy service-account topology across wild, playground and other. This is historical categorical evidence, **not** a trusted binary, process-creation or service token attestation; all host report control/DPAPI and identity flags remain false.

Do NOT export or reuse the interactive `dpapi-u` ciphertext for the service account, switch to machine-scope DPAPI or place plaintext secrets into Velocity configuration. The next approved implementation must explicitly establish a GSC service-owned secret or per-session key, a restrictive named-pipe DACL for the pinned service account, kernel process-generation identity for its clients, correct installed Java/plugin binary provenance, and anti-replay. The existing plugin remains an **inert development shell**, and `AdmissionFence` is still **unregistered** with real Velocity login events.

To avoid committing to a Windows/Java pipe library blindly, added one **disposable Windows CI native interoperability test**: `tools/velocity/ci/JavaNativePipeProbe.java` uses the JDK25 `RandomAccessFile` Windows pipe endpoint; `CI_JavaNativePipe_Interop.ps1` creates a randomly named local-only pipe under an explicitly protected **current test-user SID DACL**, starts only its own Java 25 client and exchanges a bounded 4-byte big-endian length-prefixed two-way ASCII fixture frame (maximum 2048 bytes) using JDK `RandomAccessFile.readInt()/writeInt()`, then closes all CI-owned handles and removes its temporary directory. It never creates a production named pipe listener, plugin connection, task, auth credential or world change. Windows CI independently observed successful two-way bounded frame exchange and the client's explicit success marker. This demonstrates **only** Java 25 ↔ Win32 native byte-stream framing viability; it is not JSON decoding, an authenticated peer, an actual HMAC challenge, an established secure live channel or an admission/maintenance operation. Windows PowerShell 5.1 did not expose a numeric `Start-Process` child `ExitCode` despite `WaitForExit` success; the check now fails on any **reported nonzero numeric** exit code and always requires a Java success marker and successful byte exchange. **A successful byte exchange is NOT a full secure JSON/HMAC protocol, not proof of JVM process authentication, not a production transport release, and not authorization to stop Velocity.**

Use this proven **Java 25 ↔ Windows named-pipe byte-transport feasibility** only as a starting point for next source-only framed protocol, authentication, session key handling and player fence integration. Do NOT install, enable, merge or release the bridge based on this test.


## 2026-10-19 — Java 25 native pipe Go/Java HMAC golden-frame interoperability

**Confirmed in Windows GitHub Actions (CI-only, no deployment).** After first establishing Java 25 could open a temporary Windows named pipe under an exact-current-SID DACL, the standalone `tools/velocity/ci/CI_JavaNativePipe_Interop.ps1` fixture was extended to construct independently the canonical Go `velocitybridge` message as **118 bytes**: big-endian int64 version; four length-prefixed UTF-8 fields (`wild`, `status`, `parent-100-child-101`, 32 ASCII A nonce); int64 `issuedUnix=1792267200`, `expiresUnix=1792267220`. The temporary native pipe uses the same **4-byte big-endian length limit 1..2048** as Go `velocitybridge/frame.go`, with exact-length reads and bounds/rejection on failure.

`JavaNativePipeProbe.java` compiles against the **existing unchanged production-inert** `BridgeEnvelope.java`, reads the OS pipe through JDK 25 `RandomAccessFile`, checks all 118 canonical bytes and verifies the fixed Go↔Java synthetic HMAC-SHA256 golden signature `1488217fd43660a2e0810dc60caf3f93d89d4ba4bb9b4920967f42d31fff70c5` using the test-only key bytes 0..31. It also verifies that an immediate replay fails. The Java fixture responds in a bounded length-prefixed frame, and the Windows test confirms its exact response marker, completed child process and no stderr; no production keys are generated, transferred or logged. The PowerShell runner sometimes reports a `null` child ExitCode even after `WaitForExit`, so a **present numeric nonzero** exit code fails, while a missing numeric code is acceptable only if the frame exchange and Java success marker succeeded and stderr stayed empty.

**Precisely what passed:** actual Java 25 ↔ Win32 two-way named-pipe transport, exact-SID restricted disposable pipe, Go-aligned length framing, identical Go/Java canonical encoding/HMAC verifier, and synthetic nonce replay rejection in the test-owned JVM. This is *not* a live Go↔Java connection to an installed GSC host or a real Velocity plugin, and does **not** validate runtime process identity, rotating key custody, a fresh server-issued challenge on the wire, actual protected service profiles, plugin admission event wiring, Task Scheduler suppression/restoration, Java/Bedrock session drain, or human maintenance approval. No actual task/ACL/log/secret/server/world/backups changed.

CI evidence: [Windows Java 25 authenticated golden-frame test](https://github.com/geumyi22/Geumyi-Minecraft-System/actions/runs/39151617393). PR #58 remains Draft / **NO CONTROL, NO DEPLOY**, and any eventually enabled named-pipe server must enforce kernel process identity and per-proxy authorization before accepting signed frames.

## 2026-10-19 — Java exact server-issued status nonce signer (inert)

The existing `BridgeEnvelope.java` gained **`signIssuedStatusChallenge`**, which requires a caller-supplied 32–64-character URL-safe nonce, explicit target in `wild/playground/other`, a valid JVM generation, 256-bit or stronger test key, and an issued/expires period of at most 20 seconds. The method **always signs `status`**; it has no switch for `prepare_shutdown` or `confirm_shutdown`. JUnit negative cases refuse unknown proxy, weak key, bad generation/nonce and invalid/oversized validity windows. Its deterministic MAC matches the prior Go canonical HMAC vector and the Win32 CI test now exercises this code path inside the test-owned Java 25 JVM.

This is an **inert Java helper, not a registered listener, current GSC host client or real read-only plugin endpoint**. The test key and golden vector are synthetic only; real HMAC secret custody, OS peer identity and live runtime status payload remain unimplemented. A successful MAC and even read-only status must never enable actual start/stop/restart. CI checks continue to block network listeners, shutdown calls and event registration in the no-op plugin.
