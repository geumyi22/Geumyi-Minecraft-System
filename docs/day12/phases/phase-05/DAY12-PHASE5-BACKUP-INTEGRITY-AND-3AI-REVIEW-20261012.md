# Day 12.5 — Verified local backup integrity / 3-AI review handoff (2026-10-12)

> **Production ACL apply: NOT APPROVED. PR #47: DRAFT.** This is a sanitized evidence checkpoint and review-only handoff, not a release or permission change.

## Confirmed via operator's 2026-10-12 02:05:37 +09:00 share-only report

| Check | Redacted result |
| --- | --- |
| Synthetic fixture? | **No**; real-server local read-only audit |
| Local private DACL archive SHA-256 comparisons | **10/10** match the private manifest |
| Live target DACL matches the original local snapshots | **10/10** |
| ProgramData parent DACL changed? | **No** |
| Local private backup folder remains ACL protected? | **Yes** |
| Unresolved principal ACEs across target roles | **0** |
| Any GSC ACL, service, firewall, world or backup modified? | **No production ACL modification reported** |
| Real-server `icacls /restore` attempted? | **No** |
| Independent standard-user account tested? | **No** |
| Exact ACE delta approved? | **No** |
| Security release gate | **NOT_PASSED** |

- **7 directories**: GSC_ROOT, GSC_RUNTIME, STATUSAGENT_RUNTIME, GSC_UPDATES, GSC_BACKUPS, GSC_STAGING, GSC_STAGING_CHILD each show **one inherited BUILTIN\\Users create Allow ACE**, zero explicit create Allow ACEs.
- **3 files**: GSC_SERVER_JSON, GSC_TRUSTED_DEVICES and STATUSAGENT_JAR show **zero** matching BUILTIN\\Users create Allow ACEs.
- No private original manifests, SDDL, SID listings, raw Windows paths, or archive hashes are committed, quoted or attached.

**Meaning:** The checked private archive hashes agree with the locally stored manifest and the live DACLs were unchanged when audited. This is not a proof of archive authenticity against a maliciously altered manifest, full owner/SACL/MIC restoration, or actual non-admin write/denial. The existence of a create Allow ACE is **not** an end-to-end effective-access determination.

## Fixed security scope

1. **Never edit global `%ProgramData%` parent**, unrelated directories, services, Minecraft worlds, full Golden backups, firewall or any GSC release in this PR.
2. Candidate GSC-root inheritance boundary is **provisional**. Privately confirm exact inherited ACE source and all explicit child ACEs. Existing files with no Users create Allow should not be modified merely to satisfy directory ACL policy.
3. First determine service/updater and scheduled-task write identities and paths. Host may run as LocalSystem, but installer/update/Agent identities need separate verification. Preserve read/traverse and legitimate write rights.
4. Test *actual independent standard-user identity*, not UAC-linked filtered admin token; distinguish DACL from Windows mandatory integrity and actual file operations. No test should create or replace files on live GSC paths without specific approval.
5. Reproduce real parent-child ACL graph in disposable Windows staging, demonstrate all touched objects' DACL/owner/flags restore semantics (full SACL/MIC requires distinct handling), include negative cases and rollback triggers.
6. Before any apply, present exact target list, source/desired private fingerprints, affected services, precise reversible operations, approved maintenance window and explicit user consent. Uncertain evidence means stop.

## Claude review task — code/dependency owner

Review **PR #47** at its current HEAD against main; keep all work as suggestions or an **isolated PR/branch**, not an automatic main merge. Focus on:

- Source paths in `GSC/ServerCenter/cmd/host/main.go`, `GSC/ServerCenter/cmd/setup/selfupdate_windows.go`, trusted device writes, update staging and StatusAgent runtime outputs.
- Confirm the random exclusive temp file changes actually preserve old config and update report under rename/write failure, reject preplanted reparse/paths, and don't break Windows service permissions.
- Identify *which legitimate execution identities* need write access to GSC root/Runtime/Agent/Updates/Backups/Staging and which operations require create vs modify existing files.
- Assess synthetic ACL backup/restore and the read-only local integrity auditor for fail-closed handling and insufficiently covered ancestors or directories.
- Respond with **confirmed findings, evidence (file/line), severity, minimal safe fix, and reproducible Windows CI tests**. Do not apply ACLs or deploy binaries.

## Gemini review task — independent adversarial security reviewer

Review the same PR **independently** (do not assume Claude's assessment). Focus on:

- Windows NTFS ACL inheritance, automatic inherited ACE recalculation, BUILTIN\\Users group membership interactions, absence of standard-account effective-right proof, mandatory integrity policy and reparse points.
- `icacls /save` versus `/restore` parent-relative semantics, incomplete owner/SACL/MIC rollback coverage, DACL SDDL `D:AI` normalization, and ten-object synthetic parity.
- Trust of private manifest + SHA256 as a *local consistency check* rather than a cryptographic integrity root; report redaction and accidental exposure risks.
- Challenge the GSC-root inheritance proposal using counterexamples involving updater/installer/tasks or child ACEs.
- Return **findings with severity, exact repro/mitigation, no guessed access rights**, and whether further evidence is needed. Do not change real ACLs or release anything.

## Merge/release policy

The latest Windows CI validation confirms the synthetic checks, **not** production security compliance. AI cross-reviews are pending until both independently report their analyses. Do not treat this handoff as a completed Claude/Gemini review. Keep PR #47 Draft and keep `FINAL-RELEASE-GATES.json` fail-closed. Separate firewall (15 Public-overlap broad Allow candidates) and 8-port kernel bind/owner checks remain open.
