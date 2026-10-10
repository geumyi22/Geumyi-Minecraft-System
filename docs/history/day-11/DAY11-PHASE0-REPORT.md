# Day 11 Phase 0 — Host Preflight Report

Captured: **2026-10-04 05:33 KST**

Source: user-run `Day11_Phase0_READ_ONLY.cmd` / JSON schema 1.

## Safety

The preflight declared and observed a read-only scope:

- no server-config mutation
- no Minecraft stop
- no Velocity stop
- no firewall change
- no secret collection

This report does not contain RCON passwords, device tokens, Floodgate private key contents, or signing secrets.

## Host baseline

- GSC health: **OK**
- GSC runtime version: **4.2.4**
- GSC config present
- system drive free space: **315,161,735,168 bytes**
- PowerShell: **5.1**
- `java.exe` was not resolved through the shell PATH by this preflight. This is an inventory gap, not evidence that Java/Paper was down, because multiple Paper listeners were live at the same capture time.

## Backend snapshot

| Server | Java | RCON | GDS | auto_start | update policy | note |
|---|---|---|---|---|---|---|
| Wild | online | online | online | true | managed | backend 25570 |
| Playground | online | online | online | true | managed | backend 25571 |
| Other | **offline** | **offline** | **offline** | **false** | managed | backend 25572; `accepts-transfers=false` in live properties |
| Lobby | online | online | online | true | manual | backend 25573 |

The Other state is recorded as a **host-policy/runtime drift to investigate**, not auto-corrected by preflight. Day 10 had previously passed real routing E2E; this later snapshot does not rewrite that historical result.

## Public network snapshot

All Day-10 public aliases were present at capture time:

- Java TCP 25565 / Bedrock UDP 19132
- Java TCP 25566 / Bedrock UDP 19133
- Java TCP 25567 / Bedrock UDP 19134

All three Velocity roots existed and each had:

- `velocity.toml`
- forwarding secret file present
- one Floodgate key present
- `floodgate-velocity.jar`
- `Geyser-Velocity.jar`

The three Geyser JAR hashes matched each other, and the three Floodgate JAR hashes matched each other.

## Managed-component drift found

- Wild Technology: **0.1.4**
- Other Technology: **0.1.3**
- Chemistry: 0.4.1 on Wild and Other

Technology on Other is therefore behind the current managed baseline. Do not manually replace it during Phase 0; Day 11 Update Center / managed-update work must reconcile it through the verified transaction path.

## Protection / recovery snapshot

- backup root exists
- backup data: **213,253,599,157 bytes** (~198.6 GiB)
- checkpoint root exists
- checkpoint data: **0 bytes**
- update root exists
- pending update artifacts detected by preflight: **0**

The existing backup footprint is large enough that Protection & Recovery 2.0 deletion/trash/retention work is a priority, but existing backups must not be mass-deleted automatically.

## Phase-0 disposition

**PASS for read-only baseline capture.**

This does **not** mean Day 11 is complete and does not validate any newly changed Day-11 runtime binary.

Next safe sequence:

1. finish CI/static tests for Phase 11.1 + Protection & Recovery 2.0;
2. build a host-test package;
3. install/update GSC only through backup/rollback-aware deployment;
4. verify RCON/intentional-stop/Bedrock topology/device-delete behavior;
5. test backup protect -> trash -> restore using a disposable test backup before any permanent-delete test;
6. only then continue Update Center/Fleet work and final live E2E.
