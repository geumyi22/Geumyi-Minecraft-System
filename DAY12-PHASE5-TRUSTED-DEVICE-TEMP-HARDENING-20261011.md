# Day 12.5 — GSC trusted-device temporary-file hardening (2026-10-11)

## Basis and scope

The actual Server PC **read-only** Phase5 snapshot reported inherited BUILTIN_USERS `CreateFiles/CreateDirectories` Allow ACEs on three GSC runtime/ProgramData directories, plus 38 broad inbound Allow firewall-rule candidates. These are **directory ACE facts**, not proof of effective standard-user token rights, arbitrary overwrite, symlink privilege or exploitability. The redacted local Phase5 follow-up classified 15 Public-profile, 21 Private-profile and 2 local-scoped candidates; names alone cannot justify firewall edits.

Source inspection found `cmd/host/v4_pairing.go:saveDevices` saved **hashed** GSC trusted-device tokens using a **predictable fixed filename** `trusted-devices.json.tmp` via `os.WriteFile`. Depending on actual inherited directory ACL and any Windows reparse-point restrictions, an untrusted local principal *might* be able to precreate that path; actual exploitability remains **unverified**. The live server has **no incident report of compromise**.

## Repository-only fix and tests

- Source commit `5234ca562980f980cec0f63c9d3c8a1172a966d4`: replace fixed temp write with `os.CreateTemp` in the same directory (fresh random filename, O_EXCL semantics), `Chmod(0600)`, write, `Sync`, `Close`, then existing destination replace/rename behavior and deferred temporary cleanup.
- Test commit `74fc33147b105a9e2dd9ab184d10cbcba8a71147`: synthetic-on-Windows/local-temp-dir regression with a pre-existing `trusted-devices.json.tmp` marker. Checks the untrusted fixed-name file remains **unchanged**, trusted-device JSON is correct, randomized temporary files do not remain, and an existing destination is replaced by the new content.
- This reduces pre-created predictable temp-file exposure. **It does not harden all GSC data files, change Windows ACLs, prove directory effective permissions, implement an OS ACL enforcement policy, or guarantee atomic replacement on Windows**. The fixed-temp marker regression runs against isolated test directories only.
- Source file remains associated with GSC 4.3.8 baseline code; **not installed** on operator Server PC. Any future release requires separate versioned signed release and operator-approved application.

## CI proof

- [Windows Host Test Package run 38076904639](https://github.com/geumyi22/Geumyi-Minecraft-System/actions/runs/38076904639): **SUCCESS**; hosted Windows `go test ./...` passed, including isolated fixed-temp regression.
- [System CI run 38076904666](https://github.com/geumyi22/Geumyi-Minecraft-System/actions/runs/38076904666): **PENDING**.
- [Security/SBOM run 38076904657](https://github.com/geumyi22/Geumyi-Minecraft-System/actions/runs/38076904657): **SUCCESS**.
Never label these green until the exact runs complete.

## Live decision

- **Phase12.5 final security approval stays OPEN**; human verified necessity is still 0/38; effective WFP filtering and actual nonadmin effective ACL rights unproven. The source safety improvement is not a permission to remove or disable firewall rules.
- Do not run more identical WFP scans, touch production folder permissions, expose private rule names/paths or change GSC service identity without risk assessment and rollback.
- `backend_ports_private=FAIL_UNVERIFIED_NATIVE_OWNER_ADDRESS`; `stable_release_allowed=false`; `maintenance_allowed=false`. Preserve Golden backups 4/4 and all user-accepted functional tests.
