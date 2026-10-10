# Day 12.10 — Sub PC GSC Canary eligibility and next build correction

**Observed:** real secondary-PC read-only probe at **2026-10-10 05:53:48 +09:00**. **Client-only candidate PASS**, not approval to install.

## Operator evidence

`Day12-SubPC-GSC-Preflight-20261010-055343.json` (private user-supplied file; **not committed**) reported:

| Field | Value |
|---|---|
| `schema` | 1 |
| `phase` | `day12-gsc-canary-subpc-preflight` |
| `synthetic`, `read_only` | `false`, `true` |
| `result` | **`CLIENT_ONLY_CANARY_TEST_CANDIDATE`** |
| `expected_baseline_version` | `4.3.8` |
| `candidate_version` | `4.3.9-rc.1` (tool reference, not installed) |
| Installed Client SHA-256 | `05402a24c499b9457a4d587817d1ef1393acb74992b63712970a6c94b7f65c61` |
| Published GSC 4.3.8 Client SHA-256 | **exact match** |
| `client_binary_present` / `client_config_present` | true / true |
| `host_binary_present` / `host_service_present` / `host_task_present` / `server_config_present` | all **false** |
| `issue_codes` | **[]** |
| `mutation_performed`, `install_performed`, `update_channel_changed`, `service_restarted`, `secrets_exported` | all **false** |
| `signed_canary_install_allowed` | **false** |
| `backend_ports_private` | **UNCHANGED_FAIL** |

Interpretation: the inspected computer appears suitable for a **client-only** test, with the exact published GSC 4.3.8 client binary. This does **not** prove that a future upgrade will be safe, and it is not production or live network security evidence.

## New critical source bug found BEFORE a test upgrade

The GSC **Client**, not just the Host, has an independent `compareClientVersions` in `cmd/client/main.go`. Before this audit, it split version strings at the first `-` or `+`, so a secondary PC upgraded to **4.3.9-rc.1** would incorrectly compare as **equal** to final **4.3.9**. The dashboard could then hide the final update, preventing a normal signed RC → final upgrade. The same prerelease comparison bug had already been fixed earlier in the Host, but **not the Client**.

- Patched `GSC/ServerCenter/cmd/client/main.go` to order prerelease segments below final releases, compare `rc.2` numerically below `rc.10`, reject invalid/ambiguous prerelease identifiers, and ignore build metadata for precedence.
- Expanded `cmd/client/client_update_test.go` with RC → final, final > RC, RC numeric ordering and malformed tags. Note tests use the separate Windows Client target; Go Host tests alone are insufficient proof.
- **The existing signed Canary `4.3.9-rc.1` Draft is now considered superseded for installation testing**, but it remains private and unchanged for provenance. No release tag is published or rewritten, and no existing artifact is silently replaced with different bytes using the same version.
- Prepared distinct **`4.3.9-rc.2`** CI builder `tools/day12/Build_Day12_GSC_Guard_RC2_CI.ps1` / workflow `.github/workflows/day12-gsc-guard-rc2-preview.yml`. It compiles versioned Host/Client/Setup in an isolated runner and preserves tracked/deployed 4.3.8.
- Added disposable Windows client-only transaction test `tools/day12/Test_Day12_GSC_Client_RC2_Disposable_Transaction_CI.ps1`: download and SHA-verify authentic GSC 4.3.8 client, create temporary non-production client-only installation, inject an early backup failure and confirm original remains unchanged, then execute the candidate **client-only** updater, verify new binary and automatic backup, and manually restore original client hash. Only within an isolated Windows Actions runner, never on real sub-PC. It does **not** prove all possible automatic mid-copy rollback paths.

**Current CI result:** Pending the completed distinct RC2 workflow. Do not label the transaction PASS until its actual JSON and run conclusion are verified.

## Operator-facing next step

**No new real-PC work yet.** Do not run the superseded rc.1 installer. After signed rc.2 artifact verification, a controlled **client-only** test/recovery plan with explicit user action and rollback must be prepared. The user already completed the required read-only role scan; **do not ask to repeat without a relevant installation/config change**.

The live production Minecraft Host remains GSC 4.3.8, all four server profiles and Golden 4/4 unchanged. The canonical Day12.10 `backend_ports_private` gate stays **FAIL**, later Stable release gates blocked.
