# Day 12.10 — preventive Java backend bind safety guard (source-only, not a runtime fix)

**Status:** GSC Go source committed; real host installation / runtime validation **NOT PERFORMED**.  
**Original mandatory `backend_ports_private`: FAIL, unchanged.**

## Concrete source gap

The GSC `runV4Preflight` previously checked that `server.properties` existed and inspected `server-port` equality, but did **not** check `server-ip`. As a result, a profile set to an internal Paper port could pass the existing preflight despite the on-disk Paper configuration using an empty / wildcard / nonloopback Java bind. This was a **preventive configuration gap**, not an established cause of the earlier Windows listener-table discrepancy and not proof that any server was exposed.

The operator's 02:05 live file read already showed all four existing Paper `server-ip` configurations set to loopback; the 02:20 application logs also said Java and RCON were loopback at their recorded start time. There is no evidence of a current misbinding, and changing firewall rules or restarting Paper is **not** justified by this source issue.

## Patch

- `GSC/ServerCenter/cmd/host/day12_private_java_guard.go` implements a fail-closed, read-only **pre-launch** configuration check for the four fixed Day12 private Java profiles and expected internal ports: Wild 25570, Playground 25571, Other 25572, Lobby 25573.
- A missing or unreadable `server.properties`, missing/empty `server-ip`, invalid IP or **non-loopback** address returns a preflight **fail**. The existing `startServer` honors `runV4Preflight.Overall=fail` and blocks a new start instead of automatically rewriting the file.
- Valid IPv4/IPv6 loopback values are accepted. Unrelated custom servers and legacy profiles with different ports retain their pre-existing preflight behavior.
- Hooked into `GSC/ServerCenter/cmd/host/v4_core.go` as `private_java_bind_config` and added Go tests for loopback IPv4/IPv6, wildcard IPv4/IPv6, missing/empty values, nonloopback address, invalid address, missing file and non-target profile preservation (`day12_private_java_guard_test.go`).
- This patch has **no deployed code effect** until a separately versioned and approved GSC build is installed on the server PC. No production executable, port, socket, server process, firewall, world, RCON credentials or Golden backup changed by the source update.

## 2026-10-10 — strict Java Properties shadow-key and RCON port hardening (source v2)

Further review found that the first guard could be bypassed when the four reserved server IDs had a GSC `JavaPort` not equal to their expected port, because it returned `applicable=false`. It also used `readServerProperty`, which scans only the **first** `server-ip` entry and recognizes only plain `key=value`, whereas Java `Properties.load` supports colon/whitespace separators, Unicode-escaped keys, logical-line continuation and **later duplicate properties overriding earlier values**. These are genuine **preventive source validation gaps**; **they are not evidence of real misbinding on the user's server**.

The updated `day12_private_java_guard.go`:

- Checks all fixed Day12 IDs **even if a GSC profile port drifted**: Wild Java/RCON `25570/25575`; Playground `25571/25576`; Other `25572/25577`; Lobby `25573/25579`. Unrelated custom IDs remain excluded.
- Rejects duplicate security keys, malformed/escaped key ambiguity and multiline/escaped critical values; recognizes Java-style colon or whitespace separators and decodes escaped key aliases to catch shadow definitions. It reads only `server-ip`, `server-port`, `enable-rcon`, `rcon.port`; **never reads or exports `rcon.password`**.
- Requires a literal loopback Java bind IP, the expected Java port, `enable-rcon=true` and the expected RCON port **before GSC starts the known private backend**. This is an on-disk profile safety barrier, **not proof that the RCON socket binds to loopback**, and not a current Windows LISTEN/PID inventory.
- Adds approximately **25 table-driven Go cases** for valid IPv4/IPv6 loopback, changed Java/RCON port, RCON disabled, missing keys, wildcard/nonloopback, Java `\\u` shadow aliases, colon/space separator shadows, duplicate entries and continuation lines. No existing runtime settings or server process is modified.
- The stricter fixed-ID policy is a source change requiring **separate GSC release approval**. If a legitimate older profile named `wild`/etc. intentionally uses other ports, that profile will be blocked **only after this patch is deployed**, so migration compatibility must be reviewed during the release process.
- Source/CI outcomes must be recorded from completed workflows for the updated commit; do **not** conflate them with the earlier v1 green workflow.

**References:** [Oracle Java Properties grammar](https://docs.oracle.com/en/java/javase/26/docs/api/java.base/java/util/Properties.html), [Paper `server.properties` reference](https://docs.papermc.io/paper/reference/server-properties/).

## Explicit remaining limitations

This safeguards **on-disk Java start configuration only**. It does not prove *current* OS listener addresses or process owners; it cannot stop a pre-existing process already listening; it does not constrain Java if a startup script overwrites the config after preflight; it **does not enforce or attest RCON's bind address**; and it does not address IPv6-mapped addresses or network overlays except where Paper Java's own `server-ip` is configured for loopback.

**Do not replace the strict `backend_ports_private` gate with this preflight**, do not label Day12.10 complete, and do not promote Stable/maintenance mode. Next genuinely required real verification is a separately trustworthy current listener-owner/bind method, or an explicitly operator-approved and independently tested alternative segmentation security standard.

## CI and operational rollout

The source patch triggered **Day 11 Host Test workflow [37984182804](https://github.com/geumyi22/Geumyi-Minecraft-System/actions/runs/37984182804): SUCCESS** and **System CI [37984182578](https://github.com/geumyi22/Geumyi-Minecraft-System/actions/runs/37984182578): SUCCESS**, both on `14f4412ca98baeee9f2421395eb6f86347c25ce3`. These are repository/CI test results only; no operator-machine runtime validation or new GSC installer deployment is claimed.

After source CI, do **not** silently replace the deployed GSC 4.3.8 binary: user approval, versioning, install/rollback plans and real-machine verification are mandatory.
