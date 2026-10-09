# Day 12.10 — GSC 4.3.9-rc.2 real SubPC client-only Canary final READ E2E

**Evidence captured:** 2026-10-10 **06:37:35 +09:00**, operator-supplied `Day12-SubPC-GSC-RC2-HostProxy-20261010-063730.json`. **Result: `SUBPC_RC2_AUTHENTICATED_HOST_STATUS_PASS`**, zero issues.

## Real-world GSC Client-only Canary E2E: PASS (read path only)

Earlier, the same SubPC reported:
- **05:53:** official GSC 4.3.8 Client SHA-256 match, Host exe/service/task/server.json absent, Client pairing data present; `CLIENT_ONLY_CANARY_TEST_CANDIDATE`.
- **06:24:** explicit offline signature-checked update 4.3.8 → 4.3.9-rc.2 completed; original pinned 4.3.8 Client backup SHA verified; no Host/game server change; `SUBPC_CLIENT_RC2_APPLY_VERIFIED`.
- **06:31:** installed 4.3.9-rc.2 binary correct, one correct Client process running, local loopback HTTP icon responsive, local TCP owner matched, official backup intact; `SUBPC_RC2_LOCAL_RUNTIME_PASS`.
- **06:37:** **real authenticated read from actual Server Host through existing paired Client**:
  - `synthetic=false`, `read_only=true`, `result=SUBPC_RC2_AUTHENTICATED_HOST_STATUS_PASS`, `issue_codes=[]`.
  - `local_rc2_client_identity_verified=true`, `local_no_host_role_verified=true`.
  - GET `http://127.0.0.1:8790/api/health` through the client's existing proxy: **HTTP 200**, `host_health_schema_verified=true`.
  - Authenticated GET `http://127.0.0.1:8790/api/status` using existing encrypted Client pairing, proxy adding its own Bearer auth: **HTTP 200**, `authenticated_status_schema_verified=true`, `server_list_structure_present=true`.
  - Both endpoints identify the remote GSC Host as **4.3.8**, with matching versions, `health_status_version_agree=true`.
  - `mutation_performed=false`, `client_or_service_restarted=false`, `client_token_read_or_exported=false`, `remote_host_url_exported=false`, `http_body_exported=false`, `game_server_actions_triggered=false`.

**Verified:** actual RC2 Client install, launch, local HTTP UI service, original backup, pairing persistence and remote Host **read-only** authenticated status across different client/server versions. The isolated Windows CI separately verified client backup-failure guard and manual 4.3.8 client restoration in disposable setup.

**NOT verified:** the real Client interactive dashboard's visual usability, commands/console/RCON, remote state mutations, actual Bedrock/Java network ingress, Host 4.3.9-rc.2 startup, Host-side real update/rollback, RCON bind address/owner, or any private TCP port runtime security.

**Do not request repeated SubPC preflight/apply/postcheck/HostProxy for this same unchanged build.** This specific four-step SubPC test sequence is closed as PASS.

## Host / Day12.10 gate remains blocked

- Production **GSC Host still 4.3.8**; RC2 Host is built and static/CI-tested but not deployed. No game server, Windows service, firewall, RCON credential, plugin, server.properties, world or protected Golden backup was changed to obtain the SubPC pass.
- Canonical mandatory `backend_ports_private` remains **FAIL**. A preventive pre-launch Java/RCON config guard does not provide authoritative contemporaneous IPv4 + IPv6 OS socket listener/owner evidence for the eight private Java/RCON TCP ports. Earlier provider/WFP/TCP snapshots were conflicting; do not keep re-running equivalent inventory tools or treat broader firewall Allow metadata as proof of real exposure.
- Day12.11 complete real E2E, Day12.12 live soak and Day12.13 Stable/Maintenance **BLOCKED** until their separate live gates are met.

## Next repository work (no operator action yet)

1. Audit the **Host-only** installer/self-update and tested rollback path, specifically service stop/start effects, no forced Paper/Velocity termination, protected Golden preservation, port guard interaction and signed RC2 Host preview provenance.
2. Use disposable Windows staging to validate Host-only update failure/rollback and health checks where it is genuinely reproducible; record any gap explicitly. A successful SubPC Client read-path is **not** Host deploy approval.
3. Separately plan an evidence method capable of closing canonical `backend_ports_private`, rather than treating firewall rules or config as equivalent to OS bind proof.
4. Request concrete operator authorization **only** when an actual live Host maintenance/test is ready, with precise downtime impact and verified rollback. User preference: proceed autonomously with GitHub-only work until then.

Related records: [SubPC actual apply and local runtime](DAY12-PHASE10-GSC-RC2-SUBPC-REAL-APPLY-20261010.md), [original signed offline handoff](DAY12-PHASE10-GSC-RC2-SUBPC-CLIENTONLY-HANDOFF.md).
