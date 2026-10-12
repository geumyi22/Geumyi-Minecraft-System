# Day 12.5 — GSC ACL least-privilege pre-deployment plan (review only)

**Status: DESIGN / NOT APPROVED / NOT DEPLOYED.** No operating-system ACL, firewall, services, worlds, backups, or GSC installation are changed by this source branch. The canonical `FINAL-RELEASE-GATES.json` remains blocked.

## Evidence and exact limits

The operator's private, sanitized `DAY12-ACL-DACL-ACCESSCHECK-SHARE-ONLY-THIS.json` (captured 2026-10-11 11:44 KST) reports an actual Windows DACL `AccessCheck` using the *linked UAC-filtered administrator token*:

| Target role | Requested right | DACL result |
| --- | --- | --- |
| GSC ProgramData root | add file | ALLOWS |
| GSC runtime | add file | ALLOWS |
| StatusAgent runtime | add file | ALLOWS |
| Existing `server.json` | write data directly | DENIES |
| GSC ProgramData root | add directory | ALLOWS |

This **does not prove** an independent standard-user account can create files, that MIC/integrity checks allow an actual write, or that an existing protected file can be overwritten. No write probe occurred. A prior live ActiveStore inventory showed 37 broad inbound Allow candidates, 15 overlapping Public. Local-only rule-name hints classify these 15 as 5 Windows-feature, 1 game/server, 9 unclassified; **name labels do not prove legitimacy, effective WFP behavior, or safe rule deletion**.

The GSC Host service was previously observed as LocalSystem. Directory ACL captures show inherited BUILTIN_USERS create-file/directory Allow ACEs on GSC ProgramData root, GSC runtime and StatusAgent runtime, with no observed direct BUILTIN_USERS mutating ACE on `server.json`. Do not confuse a directory's child-creation permission with the ability to overwrite an existing protected file.

## Source hardening staged separately from Windows policy

Review branch `security/day12-tempfile-acl-review-20261011`:
- `cmd/host/main.go`: host config saving now uses `os.CreateTemp` with exclusive unpredictable name, restrictive mode and `Sync` before rename. It never opens a predictable `server.json.tmp`, and does not remove the original destination when a replacement fails.
- `cmd/setup/selfupdate_windows.go`: status report writing now uses an exclusive unpredictable temp instead of `gsc-self-update-last.json.tmp`/client equivalent; on a failed replacement it keeps the previous report rather than deleting it.
- Regression tests exercise pre-planted old temp files, successful replacement, failed destination rename and temp cleanup. **Windows GitHub CI success must be confirmed before merge or release.**
- `trusted-devices.json` already uses a randomized `os.CreateTemp` path in current main.

**Residual source review:** other fixed-name temp writes exist in installer file installation paths (e.g., `copyFileStrict`, `writeEmbeddedStrict`) and other Host writes. This scoped patch **does not claim all temporary-file/symlink/reparse-point risks are removed**. Installer paths and trusted-load chain need independent auditing before widening changes. Neither this source patch nor a name change substitutes for NTFS least privilege.

## Proposed local Windows ACL change — no executable apply script yet

**Explicit operator permission and maintenance preflight are required**, even for a scoped ACL change. Never use a broad inherited deny rule or blanket recursive `icacls /reset`; such steps may block SYSTEM, administrative maintenance or Java/StatusAgent processes.

1. **Identify the real ACL source:** on the server PC, privately inspect the exact three directory security descriptors and their inherited-parent ACEs; classify effective SID and identity of GSC Host service, StatusAgent, installer and updater. Reject reparse points/symlink targets and ambiguous or unexpected service accounts. Keep sensitive paths and user identities off GitHub.
2. **Assess a genuinely non-elevated token:** use an existing standard-user context when available; record DACL and mandatory integrity distinction without writing test files or placing an untrusted executable in a privileged directory. The earlier linked filtered administrator is *not* a standard-user account proof.
3. **Map legitimate write requirements:** Host (LocalSystem), Agent, GSCM pairing storage, updater staging, logs, recovery checkpoints and maintenance/installer writes. Separate directories that need SYSTEM/Administrators write from those needing ordinary-user write. Do not remove inheritance until descendants and inherited maintenance rights are understood.
4. **Prepare exact, narrow ACL diff and backups:** capture root and target SDDL and a protected, restorable ACL export on the server PC (including parent inheritance), plus the previous installer/recovery baseline. Prefer rights adjustments on only the sensitive data directories/subtrees; retain required read/traverse permissions and SYSTEM/Administrators write. Never target all `C:\ProgramData` or blanket-deny BUILTIN_USERS.
5. **Disposable Windows staging:** reproduce the exact ACL graph in a temporary isolated directory, test standard-account denial of unauthorized create/write alongside System/updater legitimate read/write, GSC Host settings save and trusted-device save; validate rollback using only staging artifacts. A DACL AccessCheck alone is not a complete file operation test.
6. **Approval gate:** present exact directory identifiers, ACE/SID diff, expected disruption and backup/restore steps to the operator. Require affirmative, separate approval and a maintenance window before production ACL change. Do not run ACL apply based on `고고` to source-review alone.
7. **Post-change acceptance:** GSC Host/API/GSCM authentication, paired-device persistence, StatusAgent and server status, signed update staging (without applying), backup metadata, and public Java/Bedrock routing stay functional. Recheck non-admin restricted creation and preserve original evidence. No production service restart unless explicitly authorized.

## Rollback contract (designed, not exercised on production)

- Before applying, verify ACL backup integrity and that the exact ACL restoration method works in disposable staging. An `icacls /save` export and `icacls /restore` alone can behave differently with inherited ACEs and root path context; compare SDDL before/after and retain protected copies.
- Abort and restore **only the affected ACL entries** if any GSC Host/Agent/installer operation is denied, authentication fails, or required maintenance write is blocked. Do not restore/delete worlds, Golden backups, config, GSC binaries or firewall rules for an ACL-only rollback.
- Confirm effective permissions, Host functionality and audit status after rollback; do not declare rollback successful merely because an OS command exits zero.

## Separate firewall and port work

- All 15 Public-overlap firewall candidates require private owner/purpose inspection before any change. Do not delete all 37 broad Allow rules or assume names certify Microsoft. Previous negative remote probes are scoped reachability evidence, **not** proof of effective rule necessity.
- Current strict 8-port Windows socket bind+owner gate remains `FAIL_UNVERIFIED_NATIVE_OWNER_ADDRESS`. Four Java/RCON loopback settings and application startup messages are useful but do not replace contemporary kernel ownership proof. Do not rerun known-broken listener scans without a new technique.
- Day 12.13 signed automatic Stable and Maintenance gates stay blocked even if isolated source CI becomes green.

## Acceptance criteria

Source: PR review + Windows Host and setup tests green; no GSC 4.5.1 binary or official release silently updated. ACL: independent standard-user proof + approved targeted ACL application + verified legitimate Host/updater behavior + fully tested rollback. Firewall and native-port requirements remain separate. **No fabricated security PASS.**
