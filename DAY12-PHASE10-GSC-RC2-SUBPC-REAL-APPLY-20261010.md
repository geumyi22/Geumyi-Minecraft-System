# Day 12.10 — Real secondary-PC GSC Client RC2 Canary application (06:24 KST)

**2026-10-10 06:24:26 +09:00:** Operator returned original `Day12-SubPC-GSC-RC2-Apply-20261010-062426.json` (not committed). The explicit client-only secondary-PC update **SUCCEEDED**, but a post-update **runtime/UI check is still required**.

## Supported real-device observations

| JSON field | Value |
|---|---|
| `phase` | `day12-gsc-rc2-subpc-client-only-real-update` |
| `result` | **`SUBPC_CLIENT_RC2_APPLY_VERIFIED`** |
| `baseline_sha_verified` | true |
| `client_only_role_verified` | true |
| `manifest_signature_and_package_verified` | true |
| `operator_approved` | true |
| `helper_report_success` | true |
| `client_binary_updated` | true |
| `verified_old_client_backup` | true |
| `client_relaunch_reported` | **false** |
| `host_service_modified` / `game_server_modified` | **false / false** |
| `backend_ports_private` | **`UNCHANGED_FAIL`** |

This establishes that the authorized SubPC-only update helper returned success, the installed RC2 Client binary matched the pinned SHA-256, and original official 4.3.8 backup hash was validated. No Host or game server mutation was reported. It does **not** establish that the client process has actually restarted, that the local UI serves HTTP, or that pairing/Host API calls work.

## Interpretation of client_relaunch_reported=false

Source `GSC/ServerCenter/cmd/setup/selfupdate_windows.go` computes `clientWasRunning := clientExists && processImageRunning("GeumyiServerCenter.exe")`, and calls `relaunchSelfUpdateClient()` **only when that bool was true**. Thus a `false` report may simply indicate the Client **was not running** at the start. The data sent do not expose `clientWasRunning` or a distinct relaunch-error reason. **Do not diagnose crash/failed relaunch from this field alone**.

## Next read-only verification

Created `tools/day12/Day12_GSC_RC2_SubPC_Postcheck_READ_ONLY.ps1` with `.cmd` launcher. This tool **does not** launch any software or modify device settings. It:
- Rechecks pinned **4.3.9-rc.2 Client SHA-256** and identifies the single running GSC client executable without leaking PID or path.
- Checks static `http://127.0.0.1:8790/app.ico` response, without reading authenticated endpoints/tokens, plus *optional* OS local-port owner correlation.
- Rechecks client-only role, prior update-helper status, and **official 4.3.8 backup SHA-256**.
- Exports only boolean state, issue categories and hash-match results; never host URL, device token or credential.
- Reports `SUBPC_RC2_LOCAL_RUNTIME_PASS` for the local client checks, or `CHECK_REQUIRED`. Even a local PASS does **not** attest remote Host API functionality or production TCP backend bind ownership.

**Pending operator action:** On the secondary PC, launch GSC Client normally from the Start menu **if it is closed**, then run the supplied **read-only** postcheck `.cmd`, return its latest `Desktop/Geumyi-Day12-SubPC-GSC/Day12-SubPC-GSC-RC2-Postcheck-*.json`. No reinstall, new Canary version, repeated full production WFP bind scans or automatic 4.3.8 restore. Only recommend restore if actual postcheck/UI evidence shows a regression.

## Validated read-only SubPC post-update operator kit — 2026-10-10

- [Windows PowerShell 5.1 CI `37993613980`](https://github.com/geumyi22/Geumyi-Minecraft-System/actions/runs/37993613980) **SUCCESS**, including synthetic good/bad process, wrong client SHA, Host role present, missing backup and unknown role failure cases.
- Packaged one direct ZIP with only `Day12_GSC_RC2_SubPC_Postcheck_READ_ONLY.ps1`, corresponding one-click `.cmd`, `README-FIRST.txt` and `SHA256SUMS.txt`. Retrieved actual CI artifact and rechecked ZIP CRC + 3/3 nested SHA-256 checksum rows. Focused operator ZIP SHA-256: `9c296045e3dbc8b605eeaeade6e9894f35490cedebcb31bddb86e6bc01939406`.
- Exactly **one new operator action**: on the **secondary PC**, launch the normal GSC Client if it is closed, run the read-only `Day12_GSC_RC2_SubPC_Postcheck_READ_ONLY.cmd` and provide `Desktop/Geumyi-Day12-SubPC-GSC/Day12-SubPC-GSC-RC2-Postcheck-*.json`. Neither update nor recovery should be rerun at this stage.
- The tool's local HTTP probe is confined to `GET http://127.0.0.1:8790/app.ico`, with *optional* TCP PID corroboration. It reads no client-config contents or token, makes no remote Host request and does not start/restart the Client. A local PASS is not yet a real Host pairing/console E2E result.

## Real 06:31 secondary-PC RC2 local runtime postcheck: PASS

User-supplied `Day12-SubPC-GSC-RC2-Postcheck-20261010-063138.json` generated at **2026-10-10 06:31:41.8890565 +09:00** reports:
- `synthetic=false`, `read_only=true`, `result=SUBPC_RC2_LOCAL_RUNTIME_PASS`, `issue_codes=[]`.
- `installed_rc2_client_hash_match=true` (pinned 4.3.9-rc.2 client), `client_process_count=1`, `correct_client_process_running=true`.
- `client_http_icon_responsive=true`, `local_tcp_owner_observed=true`, `local_tcp_owner_correlated=true`: active local loopback GSC Client UI port 8790 is responsive, with process corroboration; **this is not a scan of production Minecraft private ports**.
- `gsc_host_role_absent=true`, `updater_last_report_success=true`, `original_438_backup_hash_match=true`.
- `updater_reported_auto_relaunch=false` remains accurately recorded as helper-reported behavior, but a **single correct RC2 process is now running**. The auto-relaunch flag cannot negate this verified current state.
- `config_read_or_modified=false`, `registry_modified=false`, `software_launched=false`, `service_modified=false`, `firewall_modified=false`, `secrets_exported=false`; `backend_ports_private=UNCHANGED_FAIL`.

**Conclusion:** GSC 4.3.9-rc.2 client-only Canary on the secondary PC passed real installed-file integrity, live local Client process/UI listener and official 4.3.8 backup verification. The *separate actual paired Host authentication and status path* has not yet been tested; do not infer this from local icon GET.

For the next, non-mutating step, the GSC Client source at `cmd/client/main.go` exposes read-only `/api/health` and `/api/status` through local Client proxy `127.0.0.1:8790`. Host code exposes unauthenticated health but requires auth for `/api/status`. Created `tools/day12/Day12_GSC_RC2_SubPC_Host_Proxy_READ_ONLY.ps1/.cmd` to perform **only two GET requests**, allowlisting these literal endpoints, auto-authenticating through the *already paired* Client proxy (no direct credential reads), and output only HTTP response codes, schema booleans and Host version (no token, URL, server detail or API response body). CI outcome and exact operator handoff to be appended after verified workflow completion.

## Mandatory safety gates unchanged

The real Minecraft server PC has **not** been updated from GSC 4.3.8 in this work. Real Day12.10 `backend_ports_private` remains **FAIL** due missing authoritative dual-stack owner-attributed IPv4+IPv6 TCP bind evidence for 8 private Java/RCON ports. 12.11 full release E2E, 12.12 real soak and 12.13 Stable **BLOCKED**. The successful client-only Canary does not lift those gates.
