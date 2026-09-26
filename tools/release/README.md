# Release publishing

The repository keeps source/configuration/documentation in Git.

Large distributable binaries are published through GitHub Releases.

## Automated flow

1. Put the current master bundle at a downloadable HTTPS URL.
2. Set:
   - `release-source.txt` — direct HTTPS download URL
   - `release-tag.txt` — release tag
   - `release-sha256.txt` — SHA-256 of the master ZIP
3. A push changing these files triggers `.github/workflows/publish-system-release.yml`.
4. The workflow verifies the master ZIP, extracts current packages, extracts GSCM APK/IPA and the GSC installer, generates `SHA256SUMS.txt`, and creates/updates the GitHub Release.

Never put credentials into `release-source.txt`.
