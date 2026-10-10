## 2026-10-10 20:58 KST — scoped proxy restart blocked by Windows listener provider

Actual operator report `Day12-Bedrock-Proxy-Restart-Precheck-20261010-205816.json`:
- `status=BLOCKED_OR_PARTIAL_RESTART_NEEDS_OPERATOR_REVIEW`
- `code=wild:PUBLIC_LISTENER_MISSING`
- `approved_pack_hashes_checked=12`, preflight of all approved 9 packs + 3 custom mappings passed.
- `proxy_restarts_attempted=false`, `proxies_verified_after_restart=0`, `steps=[]`; no backend Paper/GSC restart, Java pack/world/firewall modification.
- Current real Java/Bedrock public health is **unknown from this report**; do not infer an offline wild proxy solely from a missing PowerShell `Get-NetTCPConnection` / `Get-NetUDPEndpoint` inventory row. The earlier host investigation observed inconsistencies among OS network providers, so do not weaken release gates for private backends either.

Root script issue: the original private `Day12_Bedrock_Proxy_Restart.ps1` used `@(Get-NetTCPConnection ...).Count=0 OR @(Get-NetUDPEndpoint ...).Count=0` as a **hard** blocker for each public listener, even though other Day10 live validation already uses independent GSC application-level Java TCP and RakNet response probes.

**Replacement candidate** private ZIP `Geumyi-Day12-Bedrock-Scoped-Proxy-Restart-V2-AppProbe.zip` (no user pack bytes, not committed to public GitHub):
- Preserves all prior 12-file SHA-256 checks, V2 journal allowlist, 3 `enable-custom-content: true` checks.
- Requires exactly 3 running scheduled tasks with the exact Day10 name, action, Java arguments and working dir; exactly three matching Velocity Java process command lines, unique PIDs.
- Requires exact 3 GSC host-local `/api/v4/network/entry-status` endpoint entries for wild, playground, other with the expected public ports and **both** `java_responding=true` and `bedrock_raknet_pong=true`. This uses GSC's real application-layer TCP + UDP RakNet probes from `GSC/ServerCenter/cmd/host/network_local_api.go`, rather than treating OS provider inventories as authority.
- **Does not assert true OS port/PID attribution.** Instead `Stop-ScheduledTask` targets only the known exact task, detects one and only one Velocity Java PID going away, and `Start-ScheduledTask` must yield exactly one new PID and all three GSC app probes healthy before proceeding to the next task.
- Restart remains operator-only with zero-player check and explicit `NO PLAYERS` typed confirmation. Any process drift, mismatched task definition, missing GSC probe, or missing file hash fails closed. No force-kill, pack copy, backend/GSC restart, firewall/world/backup change.
- Python static inspection verified ZIP CRC and command presence/scope, balanced PowerShell delimiters, but **Windows runtime validation of this V2 candidate has not occurred yet**. Run `00_Precheck_V2_READ_ONLY.cmd` on actual server and proceed with `01_Restart_THREE_PROXY_V2_ONLY.cmd` ONLY if precheck returns `READY_FOR_SCOPED_PROXY_RESTART` and no players.
- Day12.11 pack delivery and client E2E still NOT verified; release gate stays blocked.


## 2026-10-10 13:19 KST — real operator approved pack staging succeeded

Operator provided paired reports:
- `Day12-Bedrock-Fix-Preview-20261010-131910.json`: `READY_FOR_APPLY_NO_MUTATION`, zero blockers, all three proxy targets empty, custom content enabled on all three.
- `Day12-Bedrock-Fix-Apply-20261010-131911.json`: `FILES_STAGED_NEEDS_PROXY_RESTART`, `APPLIED_APPROVED_SHA256_ONLY`, installed 9 approved .mcpack archives (three per proxy) and 3 approved mapping JSON files (one per proxy); reports no Paper/GSC restart, no firewall/world/Java pack changes.
- **Conclusion**: Day12.11 Bedrock pack **file placement passed**, NOT that Geyser loaded them, that any Bedrock client accepted them, or that an in-game custom-item visual passed. Stable remains blocked.

The official Geyser documentation requires restart or reload before local packs are delivered, while JSON custom item mapping instructions specifically say to restart the server. Sources: https://geysermc.org/wiki/geyser/packs/ and https://geysermc.org/wiki/geyser/custom-items/.

To minimize scope, a **private**, non-GitHub operator ZIP `Geumyi-Day12-Bedrock-Scoped-Proxy-Restart-Kit.zip` was prepared (only scripts/readme, no private packs). It provides:
1. `00_Precheck_READ_ONLY.cmd`: fail closed unless V2 12-entry journal allowlist/12 original SHA-256 hashes, three `enable-custom-content=true` settings, exactly three Task Scheduler tasks `Geumyi Day10 Velocity {wild,playground,other}` (matching working dirs/actions, Running status), and distinct owning Java process IDs for matching public TCP/UDP ports.
2. `01_Restart_THREE_PROXY_ONLY.cmd`: revalidates preflight, requires human zero-player confirmation by typing `NO PLAYERS`, then Stop-ScheduledTask / Start-ScheduledTask for ONLY those three exact Velocity tasks. Polls for new verified process+TCP/UDP ownership after each; stops and reports on unexpected state. It never changes scheduled task definitions, Paper backends, worlds, GSC, Java resource-pack URLs, firewall, backups, or protected Golden content.
3. A sanitized JSON report under `Desktop/Geumyi-Day12-Bedrock-Fix-Reports` and explicit manual review if any identity/port/partial restart discrepancy.
   
**Not executed on actual server**; the ZIP was structurally checked, but the PS1 was not independently runtime-tested on Windows. If preflight fails, do not force-kill Java or blindly restart. After successful proxy restart, actual Bedrock re-join on 19132/19133/19134 and client-side resource pack/custom-item/sound/BACAP checks are mandatory; no E2E success inferred from process listening state. Day12.10/12.7 and Stable release gates independently unchanged.


## 2026-10-10 13:12 KST forensic result and precise Apply parser fix

The real read-only operator report `Day12-Bedrock-Fix-Forensics-20261010-131249.json` confirms the prior Apply did not stage anything:
- `journal.present=false`, state `ABSENT`; `verified_approved_target_count=0`; `missing_target_count=12`; `changed_or_unapproved_target_count=0`.
- All three expected real Geyser-Velocity proxy installations present; `packs` directories each have **zero** archives; `custom_mappings` each have zero JSON files.
- Actual `enable-custom-content` scan reported `TRUE` for all 3 when the regex explicitly supports Windows CRLF.

**Identified likely trigger of original masked error:** the v1 Apply's `IsCustomContentEnabled` regex used `(?m)...$ ` without `\\r?`, so `enable-custom-content: true\\r\\n` was rejected. The independent forensics regex explicitly permits `\\r?` and reported `TRUE`. This is a source-level explanation, NOT runtime-traced proof of which exact exception was caught, since the original catch code replaced the error with `UNEXPECTED_ERROR_CHECK_LOCAL_CONSOLE`. A Windows PowerShell 5.1 synthetic regression test reproduces the old/new regex difference.

**Corrected v2 private bundle:** preserved original 4 operator-owned files unchanged with exact SHA-256; patched CRLF/LF parsing, fail-closed missing/duplicate/false cases; report human-readable per-proxy blockers instead of masking them; add SHA-256 checks of all twelve installed paths before reporting success. New v2 bundle has separate Preview / one-step Apply / hash-constrained transaction-only rollback. It does not restart proxies or modify worlds/backups/firewall/GSC/Java packs. No user pack bytes are committed to GitHub.

Given the forensic report proves no changes and prerequisites all three true, the next operator step is the **v2 one-step Preview-then-Apply script** under the real server PC. Await generated v2 JSON before proxy reload and Bedrock client E2E. `stable_release_allowed=false`.

References: https://geysermc.org/wiki/geyser/packs/ and https://geysermc.org/wiki/geyser/custom-items/ .


# Day 12.11 — Bedrock resource packs on a 3× Geyser-Velocity proxy

**Status: root-discovery correction after actual operator report 2026-10-10 11:55:08 KST. No proxy changes or in-game pack delivery proven.**

### Real first pass and exact repository-derived root fix

The real `Day12-Bedrock-Pack-Inventory-20261010-115508.json` returned `root_present=false`, and all three proxy directory checks were absent. **This was a scanner path error, not evidence that Bedrock packs are missing**. The previous scan's `GeumyiServerCenter\\Network\\Velocity` default was guessed and did not match Day10's deployed four-proxy directory.

Source-of-truth `tools/day10/finish_four_servers.ps1` line 22 sets `$proxyRoot=Join-Path $env:PROGRAMDATA "GeumyiServerCenter\\Network\\FourServer"`, copies each proxy under `wild`, `playground`, `other`, and registers scheduled tasks with these directories as `WorkingDirectory` near line 230. The inventory default now reads exactly `%PROGRAMDATA%\\GeumyiServerCenter\\Network\\FourServer` (without recording this full local path in emitted JSON). After CI succeeds, **run the corrected script once on the real serverPC; do not re-use old ZIP/version**. It is read-only, never restarts a server, and does not infer absent packs when root is missing.

If `root_present=false` again, the actual deployment has likely moved, and should be found using existing scheduler task WorkingDirectory metadata without broad disk scans. Do not re-copy packs to an invented location.




## 2026-10-10 12:01 KST — live Geyser pack directory diagnosis

The operator uploaded `Day12-Bedrock-Pack-Inventory-20261010-120128.json`.
The corrected Day10 proxy root check now returns `root_present=true`.
For **wild/19132**, **playground/19133** and **other/19134**, the report confirms:
- Velocity proxy directory, Geyser-Velocity.jar, Geyser runtime directory, config.yml, and packs directory: **present**;
- each Geyser `packs` directory has **zero** `.zip` or `.mcpack` archives;
- no matching 48-group/212-definition Geumyi custom item mapping was found;
- no actual pack delivery or Bedrock-in-game E2E has been performed.

This now provides direct evidence of a missing **Geyser-side pack delivery installation** (not a Java pack regression), consistent with the Bedrock first-login-only limitation in official Geyser docs. The report does not prove that every custom_mappings folder contains no other JSON files, or what `gameplay.enable-custom-content` is currently set to.

The assistant recovered the operator's **four original** archive/mapping bytes from their private Library. Their SHA-256 hashes match `deploy/day12-existing-pack-reference.json` exactly, and each .mcpack ZIP CRC/manifest passed offline reinspection. The operator was provided a **private, non-GitHub** ZIP bundle named `Geumyi-Day12-Bedrock-Pack-Fix-ORIGINALS.zip` with original 3 .mcpack binaries, original 212-item mapping and **Preview / Apply-without-restart / hash-guarded Rollback** commands. The scripts never change live worlds, GSC, Java resource-pack URLs, firewall or scheduled tasks; `Apply` is fail-closed on any pre-existing .zip/.mcpack in the three target pack folders, pre-existing other JSON mappings, disabled/unknown custom-content config, absent Geyser runtime files, or source SHA-256 mismatches. A local journal permits transaction-only rollback. These Windows commands have **not yet been executed on the server PC** and the private bundle is **not hosted in GitHub**. The next user/operator action is Preview on server PC, send its redacted JSON if blocked; if `READY_FOR_APPLY_NO_MUTATION`, Apply and send the resulting JSON. Proxy reload/restart and Bedrock client E2E remain separate operator gates.


## 2026-10-10 13:04 KST — operator Apply failed; no completion claim

The operator uploaded `Day12-Bedrock-Fix-Apply-20261010-130417.json`:
- `status=BLOCKED_OR_FAILED_NO_COMPLETION_CLAIM`
- `code=UNEXPECTED_ERROR_CHECK_LOCAL_CONSOLE`
- `manual_proxy_restart_required=false`; no actual Bedrock pack client E2E
- Report does **not** prove whether any subset of the 12 intended files was staged before failure. Do not retry Apply/restart or invoke rollback blindly.

**Confirmed error-reporting bug in the PRIVATE v1 `Bedrock_Pack_Transaction.ps1` bundle:** catch sanitization used regex `(?i)(\\\\|/|[A-Za-z]:)`. The `[A-Za-z]:` branch matches blocker identifiers containing a proxy label such as `wild:CUSTOM_CONTENT_NOT_CONFIRMED_TRUE`, hiding actionable preflight blockers as generic `UNEXPECTED_ERROR_CHECK_LOCAL_CONSOLE`. The underlying failure is **not diagnosed yet**.

A replacement independent **READ-ONLY forensics ZIP** (private, not committed) was prepared, with `Day12_Bedrock_Apply_Forensics_READ_ONLY.cmd` and `.ps1`. It reads existing transaction journal presence/state/allowlist, hashes 12 intended targets, counts packs and mapping files, inspects custom-content enabled/disabled/absent, and writes a sanitized JSON report to Desktop `Geumyi-Day12-Bedrock-Fix-Reports`. It does not mutate production paths. Await actual operator JSON before any Apply/Rollback/reload; neither completion nor safe rollback is inferred.


## Root cause (Geyser official documentation)

Bedrock accepts new/removed server resource packs at initial login. A normal Velocity backend transfer does **not** trigger another resource-pack negotiation, unlike Java's per-backend resource-pack request. Geyser's official docs explicitly say per-backend resource packs are unavailable natively on proxies, although a third-party transfer/reconnect plugin can simulate them: https://geysermc.org/wiki/geyser/packs/

The observed "Java pack works after Lobby → Wild/Playground, Bedrock does not" is consistent with this limitation, **but the real deployed Geyser pack paths and logs have not yet been audited**, so do not claim exclusive causality.

## Preferred low-risk solution: preload all 3 packs before Lobby

The established production topology from `Network/Bedrock/README.md` has **three independent Velocity processes**, with Geyser-Velocity at public Bedrock UDP `19132/19133/19134`, all routed to the Lobby first. Every independent Geyser must supply the same set during the first Bedrock session:

| Pack identity | Source originally supplied by operator | UUID |
|---|---|---|
| Playground sounds/textures | `Geumyi_Server_Bedrock_26.50(1).mcpack` v1.0.2 | `1b2f6fbc-e538-4c8f-8687-2e80b538e091` |
| Wild BACAP Korean | `Geumyi_Wild_Bedrock_BACAP_Korean.mcpack` v1.0.1 | `6f2ab6a2-224b-4a2c-aa6f-76ec99ccdb8f` |
| Wild ChemTech icons | `Geumyi_Wild_Bedrock_ChemTech.mcpack` v0.4.1 | `bf592f9d-3c95-57c6-8823-a5d9b53c156b` |

**Do not assume the installed files or hashes match reference attachments.** Keep the exact operator-approved bytes and versions. The Git-tracked source folders are not substitutes for live archive fingerprints without checking.

Relative location under **each actual Velocity process working directory**:
- `plugins/Geyser-Velocity/packs/` — all three distinct, verified `.mcpack` files.
- `plugins/Geyser-Velocity/custom_mappings/` — only the operator-approved 212-item Wild custom mapping when that proxy's Geyser build supports it; verify `enable-custom-content` configuration from the actual generated config. The item-mapping file is not itself a resource pack.
- Keep Java Dropbox pack URLs/server.properties untouched. No need for packs on the backend Paper's obsolete `Geyser-Spigot` path when Geyser runs at the proxy.

Pack content path comparison from Git tree: Playground and Wild-ChemTech have no overlapping non-metadata paths; BACAP and the other packs have no non-metadata paths in common. Archive-internal `manifest.json` and `pack_icon.png` being present in each **separate archive** are expected. Nonetheless, global application may influence Lobby/Other vanilla visuals, so gameplay and GUI checks are mandatory.

## Current operator next step — one safe inventory

On the real **server PC** only, obtain the latest repo `tools/day12/Day12_Bedrock_Proxy_Packs_Inventory_READ_ONLY.cmd` with its sibling `.ps1`, place them in the **same directory**, double click the CMD and supply only its Desktop `Geumyi-Day12-Bedrock-Pack-Inventory/Day12-Bedrock-Pack-Inventory-*.json` report. It inspects expected runtime folders and manifests, **never creates a pack, changes settings, reveals private paths or touches any process**. Missing folders may indicate a custom installation root; use `-ProxyRoot` only after independently finding the actual directory. No network/firewall scans repeated.

## After actual live inventory

1. Compare the exact existing .mcpack UUID/version/hash and custom mapping files on all 3 proxy instances. If the three archives are already present per entrypoint, **do not blindly reinstall**; investigate Bedrock cached packs, pack negotiation errors and Geyser runtime logs instead.
2. Otherwise make a separate, verified proxy-config-only reversible staging transaction; duplicate only approved packs in missing paths, preserve originals, back up mapping and Geyser config, avoid live changes before an assessed maintenance window. Roll back only additions made by this transaction. Never change world, Golden backups, Java server.properties, firewall or GSC Host.
3. Restart/reload **only the affected proxy instances** under no-player conditions (Geyser official instructions allow restart/reload); verify 3 public UDP entrypoints and Java routing.
4. Real Bedrock E2E: disconnect completely, rejoin on each of UDP 19132/19133/19134, accept all 3 packs during login, then visit Lobby→Wild→Playground→Other→Lobby. Verify Wild 212 custom item definitions, 33 Playground sound references, and Korean BACAP text **separately** (the language pack only works if Geyser actually passes compatible translation keys). Check vanilla look, client performance and return location.
5. Only observed in-game successes close 12.11 cases. Day12.10 native socket-owner bind, 12.7 operator offline startup, and Stable release remain blocked independently.

## Why not GeyserPackSync by default?

An unofficial GeyserPackSync transfer plugin can prompt a **reconnect** at each destination change and thereby renegotiate packs. This is a valid optional alternative but is more invasive than preload, and can affect user experience, auth, destination choice and existing position-restoration logic. Evaluate only if all-packs-at-login has unavoidable conflicting global textures or download cost; no plugin is added here.

**Sources:** official Geyser packs https://geysermc.org/wiki/geyser/packs/ ; official proxy setup https://geysermc.org/wiki/geyser/setup/self/proxy-servers/ ; official custom items https://geysermc.org/wiki/geyser/custom-items/ . 
