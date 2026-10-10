# Day 12.10 — GSC 4.3.9-rc.2 signed CLIENT-ONLY secondary-PC offline test handoff

**2026-10-10 KST. Operator input PASS and packaged handoff READY.** This is **not** a server-PC deployment, a published GitHub Canary, or Stable approval. Day12.10 mandatory `backend_ports_private` remains **FAIL**.

## Real operator SubPC baseline evidence

User-supplied `Day12-SubPC-GSC-Preflight-20261010-055343.json` generated **2026-10-10 05:53:48 +09:00** was genuinely read-only:
- `result=CLIENT_ONLY_CANARY_TEST_CANDIDATE`, `issue_codes=[]`.
- Installed Client SHA256 **05402a24c499b9457a4d587817d1ef1393acb74992b63712970a6c94b7f65c61**, exact match to official Day11 4.3.8 published Client binary.
- Client EXE and encrypted client config present; **no** Host EXE, Host service, Host scheduled task or `server.json`.
- No installation, setting/Update channel change or service restart. `signed_canary_install_allowed=false` is correctly reported by the read-only tool: this was not itself permission to apply.

## Why signed RC1 is superseded for the SubPC

`4.3.9-rc.1` CI passed Host side version comparison but retained a **Client-only** version comparator that stripped prerelease suffixes and treated `4.3.9-rc.1 == 4.3.9`. This could block a future signed RC-to-final Client update. The dedicated Client comparator and its Windows tests were fixed. Do **not** install the existing private RC1 Draft or overwrite same-version RC1 artifacts.

## RC2 source + true disposable Client-only transaction evidence

- GSC 4.3.9-rc.2 source candidate run [37990368782](https://github.com/geumyi22/Geumyi-Minecraft-System/actions/runs/37990368782) **SUCCESS**, source commit `8a02ef221ada5936e5ef6d5c0826fa8d1880d123`. Compiled Host/Client/Setup and ran Windows Go and Host Day10 non-destructive tests in a temporary copy; 4.3.8 remained the actual deployed/source baseline version.
- Official GSC 4.3.8 Client pinned SHA256: `05402a24c499b9457a4d587817d1ef1393acb74992b63712970a6c94b7f65c61`.
- RC2 Client SHA256: `c3057d6dfc2e88232a857932e960866c12fd6c8b65c40d2252ed71d6000fe111`.
- RC2 Setup SHA256: `2a623e25193d6b92dc4ec69b9ce76f098b246541c2861087f7c4911ae297602f`.
- [Disposable actual Windows Client helper transaction CI `37991677724`](https://github.com/geumyi22/Geumyi-Minecraft-System/actions/runs/37991677724): **SUCCESS**. Actual JSON independently downloaded and inspected: authentic official 4.3.8 client verified; deliberate **client-only backup failure** preserved original binary; Setup helper client-only update to RC2 succeeded in temporary Windows install dir with owned temporary registry key, RC2 Client binary hash matched, helper-created original 4.3.8 backup hash matched, and manual restore to original 4.3.8 Client hash succeeded. The CI-owned temporary registry entry was verified removed.
- **Scope limit:** The above explicitly tests early backup failure plus successful transaction and manual rollback in isolated CI. It does **not** prove every mid-copy/locked-client failure automatically rolls back; a real SubPC Client UI may temporarily close/reopen. No Host running, no real player or production environment involved.

## Strict client-only offline package (not a public Canary Release)

- [Signed offline operator-kit GitHub Actions run `37992659009`](https://github.com/geumyi22/Geumyi-Minecraft-System/actions/runs/37992659009): **SUCCESS**. It verifies official 4.3.8 Client and pinned RC2 source SHA/digests, builds a tiny standalone Go Ed25519 verifier, signs **`deployment-client-canary.json` specifically targeting `client_only`** with the pre-existing Day11 Ed25519 deployment signing secret, and tests valid-signature acceptance plus altered-signature/installer rejection.
- Key SHA256 `f21e62e87bb9d68ba05a964e0efd2e160ac249ebfbbf5f4a5125bae8f11718e3`, same historical Day11 4.3.8 release public key.
- Unlike the existing Host-oriented Canary manifest, the new offline manifest explicitly marks `target_role=client_only`, `production_host_install_allowed=false`, `public_release_published=false`, `explicit_operator_action_required=true`. **Neither version has been published to ordinary GSC updater discovery**. The existing RC1 Draft remains unlisted and superseded for Client tests.
- No Windows EXE is Authenticode signed; the **offline client-only manifest is Ed25519 signed**. This is not the same claim as Windows code signing.
- The private GitHub Actions artifact `day12-gsc-rc2-subpc-clientonly-signed-operator-kit` contained one nested ZIP. Extracted only that ZIP into `Day12_GSC_RC2_SUBPC_CLIENT_ONLY_SIGNED.zip`; verified nested ZIP CRC; **11/11** ZIP member SHA256SUMS match; independently executed OpenSSL Ed25519 signature verification against original public key. Focused ZIP SHA256: **af2fa0d5fd7b1b60a2b8ad38aaafb5c34f5a20de0cd7facc3f9d31bcfe57de74**.
- [Windows operator-kit smoke `37992954878`](https://github.com/geumyi22/Geumyi-Minecraft-System/actions/runs/37992954878) **SUCCESS**: ran the actual bundled Windows Go verifier on a disposable Windows host, checked all member digests, flipped a signature byte and verified rejection, and parsed user-facing Apply and Restore PowerShell scripts using Windows PowerShell 5.1. **The exact user-facing Apply/Restore pair has not yet been executed on the user's secondary PC**.
- Package has 12 files: `Apply .cmd/.ps1`, `Restore .cmd/.ps1`, Ed25519 signature verifier, official 4.3.8 Client recovery EXE, 4.3.9-rc.2 Setup EXE, signed client-only manifest+signature+key, `SHA256SUMS.txt`, `README-FIRST.txt`.
- No branch release, Canary/Stable promotion, server PC/GSC Host upgrade, production firewall/RCON/Golden/Java/GSCM/Bedrock/world configuration change occurred in this work.

## Exactly ONE operator action now needed

On the **verified secondary PC only**, unzip `Day12_GSC_RC2_SUBPC_CLIENT_ONLY_SIGNED.zip` and run `Day12_GSC_RC2_SubPC_Apply_APPROVAL_REQUIRED.cmd`. The script verifies signed client-only scope and all package hashes, rechecks original 4.3.8 Client SHA and absence of Host role, then **prompts for exact `UPDATE CLIENT ONLY`**, followed by Windows UAC consent. Do not run on server PC.

After it exits, send the latest `Desktop\Geumyi-Day12-SubPC-GSC\Day12-SubPC-GSC-RC2-Apply-*.json`. If Windows security or UAC blocks the launch, do not bypass blindly; send the exact error or screenshot.

For a separately instructed rollback **only if necessary**, the same kit includes `Day12_GSC_RC2_SubPC_Restore_438_APPROVAL_REQUIRED.cmd` (run as administrator with explicit `RESTORE 4.3.8` confirmation), which uses the pinned official recovery file. It is not automatically executed with Apply.

**Gate:** Even a true successful client-only SubPC Canary test would not prove real server host's private Java+RCON listener ownership. Keep `backend_ports_private=FAIL`, Day12.11 full E2E, 12.12 live soak and 12.13 Stable **BLOCKED** until their independent real-host gates succeed.
