# Day12.10 — disposable Windows Firewall CI stage result (not production)

**Status: CI STAGE PASS (narrow); LIVE GATE STILL FAIL.**  
**GitHub workflow:** [Day12 Disposable Firewall CI Stage #37982653272](https://github.com/geumyi22/Geumyi-Minecraft-System/actions/runs/37982653272) — **SUCCESS** on commit `f413f2853`.  
**Standard safety suite:** [Day12 Read-Only Safety CI #37982580208](https://github.com/geumyi22/Geumyi-Minecraft-System/actions/runs/37982580208) — **SUCCESS** on commit `93ebab791`.  
**CI artifact:** `day12-disposable-firewall-stage` / `stage-20261009-194759.json` (GitHub runner time zone, not the real server time).

## Verified CI artifact properties

Read the actual sanitized ZIP artifact, not only the green workflow label. ZIP passed CRC validation.

| Field | Result |
|---|---|
| `synthetic` | **false** (actual temporary Windows Firewall rule on CI runner) |
| `disposable_ci_runner_only` | **true** |
| `result` | **CI_LOOPBACK_SURVIVED_TEMPORARY_RULE** |
| `rule_created` | **true** |
| `metadata_matched` | **true** |
| `loopback_before`, `loopback_after` | **true**, **true** |
| `owned_rule_removed` | **true** |
| `private_ports_modified` | **false** |
| `production_host_touched` | **false** |
| `remote_host_tested`, `ipv6_tested` | **false**, **false** |
| `canonical_backend_ports_private` | **UNCHANGED_FAIL** |

The CI runner selected an ephemeral TCP port, listened at `127.0.0.1`, constructed one inbound Block rule constrained to that ephemeral port and a **non-loopback local IPv4 address** of the runner, verified its metadata, and performed a successful loopback connection after creation. The program's `finally` cleanup removed exactly its owned temporary rule and verified it no longer existed. This is **real Windows CI behavior**, but **not** evidence that another computer cannot reach that port or that any real Minecraft backend has loopback-only ownership.

## Scope limitations and mandatory next gates

1. **No remote-vantage firewall enforcement validated:** this workflow has no second host, so a local loopback TCP handshake cannot establish externally blocked access or policy precedence against Any-program Allow rules.
2. **No production equivalence:** no Paper Java, RCON, Velocity, GSC/GSCM, Bedrock UDP or Golden backup E2E was exercised. There is no comparison against the user's Windows security product / group policies / VPN configuration.
3. **No IPv6, Tailscale/overlay or DHCP address-change coverage:** a local-address scoped rule must not be assumed to cover addresses that did not exist in the disposable test. A second-host staging test needs IPv4+IPv6 and public positive controls.
4. **Rules are not safe to mass-delete:** prior server-PC ActiveStore/Java analysis shows 36 potential unrestricted Any-program Allow candidates. No verified stable rule IDs, owners, service dependencies or effective WFP classifications exist in the redacted reports.
5. **Exclusive backend binding remains unproved:** an alternative firewall-based policy is a separate security standard; it cannot silently override mandatory `backend_ports_private` or release Stable.

## Next controlled work

- **Prepare disposable two-host/VM test** with a deliberately non-loopback listening test service, observed external TCP client positive control before a narrowly scoped deny, and a verified denied remote connection *after* that deny, preserving independent `127.0.0.1` and `::1` local services. For IPv6 require separate non-loopback test address and explicit scope verification; do not assume a IPv4-scoped rule covers it.
- Before any actual host change, privately identify the 36 broad Allow rules and characterize profiles, interface/source/destination scope and service owners. Save known-good rule configuration for rollback; do not rely on ephemeral ordinal.
- At production approval time, require confirmed Golden checkpoints 4/4, no active players or update jobs, a maintenance window, exact command/affected ports, a separate out-of-band recovery path and rollback tested against GSC/local RCON/proxy/Bedrock. **Obtain explicit operator permission first**.
- Until a justified authoritative *current bind+owner* proof or a separately reviewed and approved compensating-control gate exists, leave Day12.10 FAIL; Day12.11 final release E2E, Day12.12 live soak and Day12.13 Stable **PENDING/BLOCKED**.

Files: [staging design](DAY12-PHASE10-DISPOSABLE-FIREWALL-STAGING.md), [current security assessment](DAY12-PHASE10-SECURITY-DECISION-PACKET.md), [04:38 Java firewall report](DAY12-PHASE10-JAVA-RULE-LIVE-RESULT-20261010.md).
