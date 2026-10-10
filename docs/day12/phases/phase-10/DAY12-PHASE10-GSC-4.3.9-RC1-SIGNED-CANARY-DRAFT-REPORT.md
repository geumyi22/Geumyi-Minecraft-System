# Day 12.10 — GSC 4.3.9-rc.1 Canary signed manifest / GitHub DRAFT report

**Status at 2026-10-10:** **Prepared, signed and independently verified as an unlisted GitHub DRAFT only. NOT LIVE; NOT ELIGIBLE FOR INSTALLATION YET.**

## Scope of approval and protection boundary

The operator authorized preparation of a Canary test release. This did **not** authorize updating the production Minecraft server PC or publishing to Stable. The current host remains **GSC 4.3.8**; no Paper/Velocity/Geyser/Java, GSCM, RCON, firewall, Golden checkpoint, production config, update-channel policy, Windows service or worlds were modified.

## Source and baseline verification

- [Day12 GSC Guard RC Preview #37987306874](https://github.com/geumyi22/Geumyi-Minecraft-System/actions/runs/37987306874): **SUCCESS**. CI source commit `2e5bec5f4fa0275f6bef6266f7772de67e7a14b3`. Host, Client, Setup all stamped **4.3.9-rc.1 in a disposable CI copy**, while main source and deployed version remain **4.3.8**. Go tests, GSC Day10 non-destructive Host selftest, System CI and local checksum checks PASS.
- Setup candidate `GeumyiServerCenter-v4.3.9-rc.1-Setup.exe` pinned SHA-256 `5d6a69ade04f3afb1c1e5367b5380559cadcf901eda35eb383d6cb83ed2ec539`.
- Real server-PC on-disk configuration precheck `Day12-GSC-Guard-Precheck-20261010-051837.json`: all four backend profiles Java/RCON expected ports compatible, **4/4, zero errors**. It is **not** a current TCP bind-owner/RCON isolation attestation.

## Signed GSC-only Canary DRAFT

- Separate workflow: `.github/workflows/day12-gsc-canary-draft.yml` (now **manual only**, fail closed if an existing draft or tag is found).
- Intended future release tag: `system-2026.10.10-day12-gsc439-rc1-canary`; a GitHub **draft** can temporarily have an internal `untagged-...` placeholder before publication. **Never publish unless final tag equals the signed manifest `release` field.**
- **Only GSC** in `deployment-canary.json` (`schema=1`, `channel=canary`, `repository=geumyi22/Geumyi-Minecraft-System`, `components.gsc.version=4.3.9-rc.1`, `kind=gsc`, `targets=[host]`, `requires_restart=true`, pinned Setup hash/size). No plugin or mobile update components, and no `deployment-stable.json`.
- Manifest signed using the **pre-existing** repository `DEPLOYMENT_ED25519_PRIVATE_KEY_B64` secret, not a newly generated replacement. The derived public key compared equal to `deployment-public.pem` from the published Day11 GSC **4.3.8 beta** release. Signing and verification with the previously released key completed successfully; private key not exported.
- Draft assets (6): `GeumyiServerCenter-v4.3.9-rc.1-Setup.exe`, `deployment-canary.json`, `deployment-canary.json.sig`, `deployment-public.pem`, `SHA256SUMS.txt`, `README-NOT-FOR-INSTALL.txt`.
- Windows PE/installer is **NOT Authenticode-signed**; a signed update manifest is not equivalent to Windows code-signing.

## Read-only independent DRAFT audit (actual GitHub uploaded bytes)

- Initial signing workflow [#37988376060](https://github.com/geumyi22/Geumyi-Minecraft-System/actions/runs/37988376060) **FAILED at final lookup only**: `gh release create --draft` succeeded but GET-by-tag returned 404 for GitHub's unpublished `untagged-...` placeholder. No user-visible/public live release was created.
- Initial audit failed to find the draft with a read-only GitHub Actions token. The corrected audit uses authenticated releases-list API visibility (the script only issues read GET operations).
- [**Day12 GSC Canary Draft Read-Only Audit #37988929955**](https://github.com/geumyi22/Geumyi-Minecraft-System/actions/runs/37988929955) **SUCCESS**:
  1. Exactly one matching draft by pinned title and source commit, `draft=true`, `prerelease=true`, `published_at=null`, six required assets, no Stable manifest.
  2. Read back each of the six actual attached assets from the authenticated GitHub release-asset API.
  3. `sha256sum --check SHA256SUMS.txt` PASS, independent expected Setup hash PASS.
  4. `openssl pkeyutl -verify -rawin -pubin` with the attached public key confirms the uploaded `deployment-canary.json.sig` over the uploaded `deployment-canary.json` PASS.
  5. The uploaded JSON contains **only** the expected GSC host component, exact Canary channel and pinned release identity.
- No activation, update API apply, automatic restart, Studio Canary promotion or Stable release was run.

## Exact next stage, before asking the operator

**GitHub/GSC-only preparations completed.** The draft is intentionally **not discoverable** by normal GSC release discovery, which ignores drafts.

1. Before a secondary Windows computer can test **normal signed GSC update discovery and rollback**, a tightly controlled published *Canary* prerelease (not Stable) with the exact signed manifest release tag and trusted public key must be made accessible. Verify no fleet-wide automatic application and that only a deliberately configured Canary test GSC can select it. Do not publish merely to turn a CI result green.
2. Verify a **known-good GSC 4.3.8** executable/installer and rollback route on that test PC. Confirm user-approved test host, administrator/service effects, time window, active tasks, free disk, config safety, original binary hashes and restoration plan. No need to touch the Minecraft production host.
3. Once a safe, controlled test-host rollout is ready, ask the operator **one direct action** on the secondary PC (and send exact install/rollback instructions). Do not require repeat read-only port/WFP/firewall scans.
4. A successful secondary-device signed update/rollback **would not** establish actual eight private Java/RCON OS socket address/owner proof on the production server. Keep strict `backend_ports_private=FAIL`, Day12.11 release E2E, 12.12 real soak and 12.13 Stable **PENDING/BLOCKED** until their independent real-host gates are satisfied.

## Non-negotiable failure / rollback rules

On any mismatch of Canary release tag versus signed JSON `release`, public key versus on-host trusted key, Setup SHA256, incomplete artifact set, absent GSC 4.3.8 rollback, service/app health, or accidental public exposure of a draft prior to approval: **stop**, leave live 4.3.8 untouched and report the blocker. Do not disable security checks or silently substitute a firewall policy for exclusive bind evidence.
