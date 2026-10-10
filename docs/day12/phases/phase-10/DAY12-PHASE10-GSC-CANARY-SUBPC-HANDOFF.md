# Day12 — GSC 4.3.9-rc.1 Canary test: one-step secondary-PC read-only preflight

**State:** Canary release remains signed Ed25519 **GitHub Draft**, unpublished; no automatic GSC update discovery, no live installations. **One operator action requested: secondary-PC read-only compatibility JSON**. Strict `backend_ports_private` **FAIL**, Stable still blocked.

## Confirmed pinned baseline

GitHub published Day11 4.3.8 beta release: `system-2026.10.07-day11-gsc438-beta`. The official release asset SHA256 references were checked in CI:
- Published `GeumyiServerCenter.exe` (4.3.8) SHA-256: `05402a24c499b9457a4d587817d1ef1393acb74992b63712970a6c94b7f65c61`.
- Published `GeumyiServerCenter-v4.3.8-Setup.exe` SHA-256: `288aeb4f0cf75691a997411911bf2fddac1b61644e915845bb6161468080a039`.
- New 4.3.9-rc.1 candidate Setup in signed **draft**, verified SHA-256: `5d6a69ade04f3afb1c1e5367b5380559cadcf901eda35eb383d6cb83ed2ec539`.
- The last release and Canary draft used the same pre-existing Ed25519 deployment-public key. **This is manifest authentication only, not Windows Authenticode.**

## New tool and validation

- PowerShell `tools/day12/Day12_GSC_Canary_SubPC_Preflight_READ_ONLY.ps1` and one-click `.cmd`, both explicitly read-only.
- Checks original Windows install registry, expected GSC client executable SHA256 against signed-channel 4.3.8 published asset, **presence only** of encrypted-client-config file (never opens it), host executable/service/task and server config to distinguish client-only secondary PC from a real Minecraft host.
- Does **not** read any client token/credentials, execute a GSC application, invoke GSC update API, install release binaries, change active channels, touch player sessions, stop/force-kill services, audit/firewall, config or backups. Exports statuses, SHA256, boolean role evidence, bounded issue codes; no absolute paths or remote URLs.
- `CLIENT_ONLY_CANARY_TEST_CANDIDATE` only means the PC appears to be client-only and the binary matches the pinned 4.3.8 asset. It is **not** authorization or proof of signed updating / safe rollback.
- Unknown role, absent installation registry, non-matching client SHA, missing client config, and host binary/service/task or server config produce **`CHECK_REQUIRED`**; fail closed and do not instruct operator to reinstall.
- [Day12 GSC Canary SubPC Read-Only Handoff Kit CI #37989602640](https://github.com/geumyi22/Geumyi-Minecraft-System/actions/runs/37989602640): **SUCCESS**; independently confirmed signed-release reference digests and Windows PowerShell 5.1 script syntax + synthetic fail-closed behavior.
- The standard [Day12 Safety CI #37989515903](https://github.com/geumyi22/Geumyi-Minecraft-System/actions/runs/37989515903) also contains the synthetic role-negative tests; check its own final outcome independently.
- Downloaded artifact `Day12-GSC-Canary-SubPC-READ_ONLY` and verified the nested ZIP CRC, **three sidecar SHA256 entries 3/3 match**, with only `.cmd`, `.ps1`, `README-FIRST.txt`, `SHA256SUMS.txt`. No setup EXE, DLL, JAR or installer. Focused outer user ZIP SHA-256: `68b8e8917aeadca3e129fe865a809dd8a8e54f876f99775329b56bf0c1f222f3`.

## Exactly one operator action, then stop

On the **secondary PC**, not server PC, extract `Day12_GSC_Canary_SubPC_READ_ONLY.zip`; run `Day12_GSC_Canary_SubPC_Preflight_READ_ONLY.cmd` once. Send only latest `Desktop\Geumyi-Day12-SubPC-GSC\Day12-SubPC-GSC-Preflight-*.json`.

Do not run the unsigned GSC 4.3.9-rc.1 draft setup or change the device's update channel. Do not rerun past server TCP/WFP/firewall scans, or install new network infrastructure. If role/hash preflight is CHECK_REQUIRED, send the report without configuration changes.

## What remains before a REAL secondary-PC Canary update

1. Assess the SubPC JSON and confirm this machine has no Minecraft Host service/config/process and has the expected 4.3.8 binary.
2. On a disposable Windows machine test the 4.3.8 client-only update helper's backup/restore behavior, including clean exit, failed update rollback, and no uncontrolled host process task kills.
3. Prepare a verified rollback package/restore and assess service/update window risks; the self-update helper's client closure potentially affects all `GeumyiServerCenter.exe` instances on the test PC. Do not claim it is interruption-free.
4. Decide whether to use offline signed draft asset test (must preserve Ed25519 verification) or a precisely controlled published Canary update, ensuring other opted-in Canary devices cannot be inadvertently updated. The draft currently is excluded from GitHub's ordinary discovery.
5. Ask the user for explicit real-machine update action **only after** those gates are validated. No live GSC 4.3.8, Paper/Velocity/Bedrock/GSCM, firewall or protected Golden changes yet.

Reference: [signed Canary draft review](DAY12-PHASE10-GSC-4.3.9-RC1-SIGNED-CANARY-DRAFT-REPORT.md).
