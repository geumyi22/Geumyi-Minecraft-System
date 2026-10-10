# Day 12.10 — Live Windows TCP listener state-0 evidence (2026-10-11)

## Provenance and execution
Operator-provided sanitized `DAY12-LISTEN-STATE-PROBE-SHARE-ONLY-THIS.json`, generated `20261011T030134+0900`, schema 31, script version 3.1.0; `read_only=true`, `synthetic=false`. Windows build 26220; PowerShell 5.1.26100.9587. No production restart, adapter/firewall/ACL/server/world/backups changes. Two ephemeral self-connected loopback probes and one GSC fleet GET. Native helper temporary build directory removed, leftovers=0. **The operator's JSON is not stored in the public repository.**

## Strongly corroborated observations
- IPv4 AND IPv6 self-owned, loopback-bound temporary TCP listeners each had **exactly one native owner-PID-matching local listener-signature row** (remote wildcard, remote port zero, own PID), with **raw native TCP state=0**, while accepted-side and client-side established connections were separately found, one of each. `.NET` called the listener endpoint `Unknown`; `Get-NetTCPConnection` returned numeric 0 / `UNKNOWN`. Native queries v4/v6 succeeded (return code 0).
- Previous v3 scans searched for `LISTEN=2` only and therefore missed these present but state-0 rows. The observation is a *state reporting anomaly*; it does **not** prove the causal agent (OS Insider build, third-party filters, NSI, etc.).
- Native signature census: IPv4 42 state-0 listener-signature rows, IPv6 22; this signature is a **heuristic**, not itself proof of the Windows LISTEN state, though own controlled probes support the interpretation.
- GSC localhost 8790: one IPv4 loopback state-0 signature row, owner role `not_java`. Public Velocity Java 25565/25566/25567: each two state-0 rows, IPv4+IPv6 wildcard, role `velocity`.
- GSC reported wild, playground, lobby online; other offline. Wild 25570/25575, playground 25571/25576, lobby 25573/25579 each has exactly one IPv4 loopback state-0 signature row owned by a Paper process. In each online game's game port and RCON port, owner PID matches; 6/6 online private ports strongly corroborated by consistent configuration/role/owner/loopback signature. Other 25572/25577 absent, consistent with offline state and not a pass for its bound ports.
- Java process role counts: Paper=3, Velocity=6, StatusAgent=1. Existing GSC actual config port mismatches=0 (from prior v3).

## Scope and release decision
`backend_ports_private=FAIL_UNVERIFIED_NATIVE_OWNER_ADDRESS` and `stable_release_allowed=false` **remain unchanged** in evidence JSON. This v3.1 finding permits a **human-reviewed, narrowly scoped alternative proof proposal** for the six *currently online* private TCP sockets. It is not an automatic 12.10 PASS, never verifies all eight sockets simultaneously because the Other server was offline, and does not close 12.5 effective ACL/firewall nor 12.7 real offline boot nor 12.11 crash/Canary nor 12.13 release gates. Do not substitute signature-only evidence for effective network exposure review.

## Potential follow-up
1. Avoid further retries of netstat-only `LISTEN` scripts. If needed, independently verify the raw-state-0 loopback binding model by reviewing the v3.1 script source and whether its owner PID, endpoint parsing and signature exclusions are valid.
2. To identify root *cause*, evaluate Windows build 26220 change history and software/filtering layers **without disabling security, restarting the production server or rolling back Windows**. Do not assert root attribution without discriminating data.
3. An operator can approve scoped acceptance of v3.1 alternative owner/loopback evidence with documented caveats; the release validator and authoritative Stable gate must remain unchanged until every outstanding gate has its own approved evidence.
