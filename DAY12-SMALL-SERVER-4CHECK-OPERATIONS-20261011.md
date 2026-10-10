# Day 12 — four-check small-server operational closeout (2026-10-11)

## Operator scope decision

The operator's newest instruction: **Other server may be treated as accepted by equivalence with Wild / Playground / Lobby for routine operational closeout**, with **no additional Other-specific live tests requested**. This is an **operator waiver / accepted equivalence**, not an executed Other runtime test. The last actual v3.1 socket observation had `other=OFFLINE`, so Java `25572` and RCON `25577` were **not live-observed**.

Target: small friend/family Geumyi Minecraft server, about 5–6 concurrent players. Accept existing healthy ordinary operations; stop repeating Java/Bedrock route, pack, console, client control, cache and Golden backups with unchanged configuration. Do not silently label unobserved signed releases, network paths or destructive tests as E2E successes.

The operational record is [`deploy/day12-small-server-four-check-operational-acceptance.json`](deploy/day12-small-server-four-check-operational-acceptance.json). This is **not a substitute** for [`FINAL-RELEASE-GATES.json`](FINAL-RELEASE-GATES.json); those production release gates are unchanged.

## Four requested tasks

| Priority | Target | Evidence-based scoped result | Next action |
|---|---|---|---|
| 1 | Private Java/RCON traffic | **OPERATOR-ACCEPTED operational PASS (Wild/Playground/Lobby)**: actual v3.1 real-host 6/6 IPv4 loopback Paper owner/RCON same-owner *state-0 listener-signature* rows, and previously tested LAN/Tailscale IPv4+IPv6 private 0/8 with public-positive controls. Other 2/8 waived by equivalence **not observed**. | No repeated native netstat/TCP inventories. Do not change strict native eight-port requirement for formal Stable release. |
| 2 | Windows firewall | **Focused review OPEN**: earlier read-only ActiveStore inventory saw 269 inbound Allows and 38 broad Any/Any/Any, of which **15** overlap Public-profile. There are 21 Private-focused and 2 local-address-scoped. Rule names are **hints**, 0/38 independently proven necessary. | Review **15 Public-tier rule identities only** using the existing private local CSV. Do not rerun enumeration, auto-disable broad rules or publish rule names. |
| 3 | GSC ProgramData/Agent ACL | **Source improvement CI PASS; actual effective ACL still OPEN**: three GSC folder targets show inherited BUILTIN_USERS create-allow ACEs; system service runs LocalSystem; two directly checked files had no broad direct mutating Allow reported. | Do not change ACL inheritance or OS service account blindly. Future legitimate maintenance should assess effective user token rights / staged privileged data paths and contain rollback. |
| 4 | Backups and rollback | **OPERATOR-ACCEPTED scoped PASS**: 4/4 full Golden protected, 84/84 cached file digest/size, actual disposable GSC + Paper crash recovery CI [38075813601](https://github.com/geumyi22/Geumyi-Minecraft-System/actions/runs/38075813601), isolated Host successful update/manual restore [37996301163](https://github.com/geumyi22/Geumyi-Minecraft-System/actions/runs/37996301163) and failed-update auto rollback [37997022476](https://github.com/geumyi22/Geumyi-Minecraft-System/actions/runs/37997022476). | Keep all Golden backups, no destructive production restore/redundant hash reruns. |

## Latest code safeguards, still not deployed to real Host

- GSC TCP `portPID`: original listener-only table class retained, no `state==2` requirement (operator OS had raw 0); conflicting/invalid PID fails closed. Corrected Windows Host CI [38077143465](https://github.com/geumyi22/Geumyi-Minecraft-System/actions/runs/38077143465) and Security CI [38077143404](https://github.com/geumyi22/Geumyi-Minecraft-System/actions/runs/38077143404) SUCCESS; full System CI [38077207880](https://github.com/geumyi22/Geumyi-Minecraft-System/actions/runs/38077207880) **SUCCESS** after earlier concurrency cancellations. This does not prove the native state-0 source or complete Windows listener truth.
- GSC trusted-device persistence uses exclusive unpredictable temporary file to avoid predictable pre-planted `trusted-devices.json.tmp`. Windows Host CI [38076904639](https://github.com/geumyi22/Geumyi-Minecraft-System/actions/runs/38076904639), Security CI [38076904657](https://github.com/geumyi22/Geumyi-Minecraft-System/actions/runs/38076904657), System CI [38076904666](https://github.com/geumyi22/Geumyi-Minecraft-System/actions/runs/38076904666) SUCCESS. New source is **not** installed on live GSC 4.3.8.
- Existing 12.7 cached files and disposable blocked upstream update-source integration pass their own narrow scope. Actual server-PC full disconnected-network startup remains not tested; don't cut a household connection to prove it. The operator previously accepted the uninterrupted routine soak; no repeated 8-hour run is needed, but formal instrumented Stable gate is separate.

## Single bounded offline follow-up for checks 2 and 3

A **locally generated, separately shared** read-only ZIP `Geumyi-Day12-SmallServer-4Check-Offline-ReadOnly.zip` (SHA-256 `f4d9184cba35f2f7a87bcad1224b6d84008dffcd71347c5a914c07fa1ae75eac`) was prepared. It contains `README-KO.txt`, the Windows CMD launcher, the ASCII-only UTF-8 BOM PowerShell source and file digests. ZIP CRC and SHA256SUMS verified and prior *sanitized* source JSON shape cross-checked (**38/15/21/2** and **3 inherited create-allow ACL targets**). Its PowerShell 5.1 script **has not been executed on Windows by the author**, so a real Windows self-test is built into the launcher; if it fails, no existing capture is processed. This tool never enumerates fresh firewall/ACL data: it reads only the **already produced** public decision JSON, local PRIVATE identity CSV, and triage share JSON, validates candidate ordinals and profile assignment, produces a **category-only redacted summary JSON** of the fifteen Public-tier candidates and prior ACL category counts, and keeps all raw rule identities private on the user's Server PC.

It cannot itself determine actual rule necessity, effective Windows Filtering Platform packet decisions, or effective standard-user ACL rights. The operator must not upload `LOCAL-RULE-IDENTITIES-REVIEW-DO-NOT-SHARE.csv` or the original private identities file. The next shareable result name is `DAY12-SMALL-SERVER-4CHECK-SHARE-ONLY-THIS.json`.

## Final decision boundary

- **1 and 4 are scoped operational PASS**; **2 and 3 require a focused risk decision**, not automatic bulk OS changes. Other-server waiver does not authorize treating other Java/RCON as physically observed.
- Existing `FINAL-RELEASE-GATES.json` remains **BLOCKED** with `phase_12_10_backend_ports_private=FAIL_UNVERIFIED_NATIVE_OWNER_ADDRESS`; `stable_release_allowed=false` and `maintenance_mode_allowed=false`.
- No firewall/ACL alterations, GSC/GSCM installations, forced restarts, private reports, OS commands or new operator-host tests were performed to write this acceptance record.
