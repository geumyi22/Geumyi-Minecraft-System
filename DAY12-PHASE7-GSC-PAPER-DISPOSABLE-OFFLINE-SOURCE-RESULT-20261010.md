# Day 12.7 — Actual GSC 4.3.8 + Paper 26.3 boot with blocked update source on disposable Windows CI

**Date:** 2026-10-10 KST. **Workflow:** [Day12 Phase7 Disposable Real GSC Paper Offline Update Source, run 38017215282](https://github.com/geumyi22/Geumyi-Minecraft-System/actions/runs/38017215282), conclusion **SUCCESS**. Sanitized run output artifact: `day12-disposable-real-gsc-paper-offline-source-result`, ID `11656627512`. Read the **actual JSON inside** that artifact, not merely the workflow outcome: `result=DISPOSABLE_REAL_GSC_PAPER_PROCESS_SCOPED_OFFLINE_SOURCE_PASS`.

## First real two-process integration evidence

1. A disposable GitHub-hosted **Windows** runner downloaded the **public official** [`mc-2026.09.26-v3` release](https://github.com/geumyi22/Geumyi-Minecraft-System/releases/tag/mc-2026.09.26-v3) Playground archive `Geumyi_Playground_Paper26.3_Current_2026-09-26.zip` and verified its full expected SHA-256 `6198ad133c37667a4a0a92567f204c4c24e5f265864f8dd19605407c6e3ced4b`. Exactly **one** Paper JAR (about 63.7 MB) was extracted into runner-only storage. No production server, world, backups, plugins, tokens, Dropbox links or configs were used.
2. CI installed Java **25** (per `Servers/Playground/PAPER_26.3_INFO.json`) and booted **real Paper 26.3** on a new loopback-only test server. It observed a real open local Java TCP listener, and submitted `stop` to terminate this initial boot gracefully, thereby preparing any first-run dependencies. **No existing user's world** was copied.
3. CI compiled **actual GSC Host 4.3.8 source** into a disposable Windows executable and started it with a completely separate **runner-only** config: `stage-playground`, unused test loopback port, one managed updater, **no auto-start Agent**, **no mobile network**, **no restart on crash**, and a **CI-only** public Ed25519 key. This was NOT a second process on the real ServerPC.
4. To simulate unavailable upstream update API without affecting the user or CI OS networking, ONLY the GSC child process inherited an intentionally invalid `HTTPS_PROXY` pointing at a nonlistening loopback port. Therefore the test is **process-scoped failed update-source connectivity**, **NOT full Windows offline mode**. CI checked GSC `/api/health` reports **4.3.8**, issued a real local `POST /api/server/action` for its disposable Playground, and received HTTP **202**.
5. GSC's real `/api/v4/update/status?id=stage-playground` reported **`phase=error`** matching the blocked upstream update-source condition. The GSC-triggered **real Paper** process nevertheless came back ONLINE with the dedicated loopback Java listener. Its trusted original `paper.jar` file digest did **not change**.
6. CI harvested a bounded evidence artifact and returned full workflow **SUCCESS**. No fake all-phase PASS, no GSC Stable promotion or release gate edits. No VM/Windows Sandbox needed on user's serverPC.

## Scoped acceptance (new)

| Check | Observation |
|---|---|
| Official Playground Paper archive verified | **PASS** |
| Real disposable Paper online boot, normal stop | **PASS** |
| GSC 4.3.8 started and identified via HTTP | **PASS** |
| GSC authorized local start action HTTP 202 | **PASS** |
| Managed updater upstream failure observed | **PASS** |
| GSC still launched real Paper while upstream unavailable | **PASS** |
| Pre-existing stage Paper JAR byte-identical | **PASS** |
| Operator's actual serverPC without Internet booted | **NOT TESTED** |
| Completely disconnected VM/OS networking | **NOT TESTED** |
| Operator's actual 84-file known-good cache exercised to start server | **NOT TESTED** |
| Real Java+Bedrock player routing and packs | **NOT TESTED** |
| 12.5 effective policy / 12.10 Windows native RCON/Java owner+bind | **OPEN** |
| Stable / Maintenance authorization | **BLOCKED** |

**Safety:** No runtime changes or remediation were applied to operator's Playground, Wild, Other, Lobby, Host 4.3.8, GSCM, firewall, world or Golden 4/4. The GSC executable in the **GitHub disposable runner** executes its normal startup initialization, which can include firewall synchronization **on the disposable runner only**. It must **not** be copied to the production server and launched as a second Host.

## Relation to real 2026-10-10 11:21 Sandbox capability JSON

The real operator submitted `Day12-Sandbox-Capability-READ-ONLY.json` (2026-10-10 11:21:47 KST), `synthetic=false`, `result=SANDBOX_CAPABILITY_REVIEW_REQUIRED`, with exactly four `missing_prerequisites` flags:
- `sandbox_binary_found=false`;
- `sandbox_feature_enabled=false`;
- `virtualization_enabled=false`;
- `single_paper_jar_found=false`.

All other checked flags (GSC Host service/exe, Playground server root, Java, public key, RAM, disk) were true. This **does not** establish a real missing Paper JAR: the script uses conservative filename and location matching and may miss custom names. It does establish **the checked serverPC cannot run the proposed Windows Sandbox route without additional changes**. Do **not** enable optional hypervisor features, BIOS virtualization, alter Windows policy, or rename/move the user's Paper JAR to satisfy this preflight.

**Next:** preserve all previous real evidence (12.0 Golden 4/4, 12.7 cache SHA256 84/84, four remote private-port nonreachability paths, 8/8 GSC HTTP401) and mark the new **disposable actual GSC+Paper update-source-outage integration test PASS only within CI scope**. Full 12.7 `offline_known_good_startup` **remains OPEN** for a genuine isolated/no-network operator runtime using known-good cache, and later 12.11 real clients / 12.12 soak remain independently required. Fail-closed Stable unchanged.
