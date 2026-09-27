# Source and public-repository security review

## Current tracked source

Initial recovery review covered the final tracked source tree, decoded GSCM files, source templates, Java/Bukkit defaults, build scripts, tests and resource-pack text/assets.

Checks included Gitleaks/targeted credential patterns, Discord/RCON/API/device/pairing/GitHub/Apple/keystore/private-key patterns, configuration inspection, disallowed-extension checks and archive/source comparisons.

No real credential was detected in the reviewed current-source set. Previously flagged Discord IDs in GSC tests are synthetic fixtures, as are pairing/test-secret values. Agent templates and GDS defaults contain blanks or explicit placeholder values. Never commit configured runtime copies.

## 2026-09-27 public-repository follow-up

The repository was changed from Private to Public. A follow-up review was therefore performed on the newly recovered Day-3 material and the existing release bundle.

- Day-3 CLEAN recovery archives checked: GST HOTFIX source, Technology 0.1.3 reconstruction, Chemistry 0.4.1 reconstruction, StatusAgent 0.5.4 reconstruction, and sanitized Wild/Playground configuration evidence.
- 108 text-like files across those CLEAN archives were checked for email addresses, GitHub/Discord token forms, private-key headers, Dropbox share URLs, Windows user-profile paths, Korean phone-number patterns and resident-registration-number patterns. No matches were found.
- The existing 2026-09-26 master release was recursively inspected through nested archives. No real GitHub/Discord token, private key, bearer credential, Korean phone number or resident-registration number was detected. Apparent email/IP/token-like matches reviewed there were third-party metadata, generic examples, loopback/private-network examples or synthetic test fixtures.
- Recovered server configuration published under `Servers/Wild` and `Servers/Playground` is historical evidence only. RCON/management secrets and historical resource-pack share URLs are explicitly redacted.

## 2026-09-27 full-history follow-up

A 66-commit history pattern audit was run after the repository became public. High-risk patterns checked included GitHub/Discord token forms, private-key headers, bearer credentials, Korean phone numbers, resident-registration-number patterns, Windows user-profile paths and Dropbox share URLs.

- No GitHub/Discord token, private key, bearer credential, Korean phone number or resident-registration-number pattern was found in the reviewed commit diffs.
- One Windows user-profile example path was found in the GSC client dashboard history and was also still present on `main`. The current file was sanitized to the generic example `C:\\Minecraft\\Server` in commit `0363836f66bd6c335ce794f71365f1bc561432c5`.
- The old Dropbox release-source URL appears in two historical commit diffs. It is not present in the current tree.
- 64 of the 66 reviewed commits use a non-GitHub-noreply author email in Git metadata. The address itself is not repeated in this document.

These findings do not imply that pattern matching can prove absolute absence of personal information. The current tree and future commits should continue to be reviewed before publication.

## Public Git-history caveats

The **current tree being clean does not remove data already present in Git history**.

- A number of commits use a non-noreply author/committer email in Git metadata. That email is visible on a public repository even when it does not appear in current files. For future commits, enable GitHub's private-email setting and use the account's GitHub noreply commit address.
- A deleted historical `release-source.txt` commit contains an old Dropbox shared URL in its diff. Deleting the file from `main` did not erase the URL from Git history. Revoke that Dropbox shared link if it has not already been revoked.
- History rewriting is intentionally **not** performed automatically. It changes commit SHAs and can affect releases, Actions references and clones. Do it only as a separately approved maintenance operation after credentials/share links have been revoked.

## Publication rules

Do not commit or publish:
- configured Bot/API/device tokens or pairing state
- RCON passwords or management secrets
- keystores, signing certificates or private keys
- runtime logs containing player/IP/account data
- private local paths/configs when they identify a real workstation user
- configured Agent/GDS/GSC runtime state

Source examples must use placeholders or sanitized documentation values.

Pattern scanning cannot prove absence of every possible secret. If any real credential or share link is discovered in old history or Releases, revoke/rotate it first; deletion alone is not credential remediation.
