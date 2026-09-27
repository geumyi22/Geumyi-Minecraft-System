# Release publishing

The repository keeps source/configuration/documentation in Git. Large distributable binaries are published through GitHub Releases.

## Manual Actions flow

1. Put the current master bundle at a downloadable HTTPS URL.
2. Update these tracked metadata files when the baseline changes:
   - `release-tag.txt` — default release tag
   - `release-sha256.txt` — expected SHA-256 of the master ZIP
3. Open **Actions → Publish Geumyi System Release → Run workflow**.
4. Enter:
   - `source_url` — required direct HTTPS download URL
   - `tag` — optional override; blank uses `release-tag.txt`
   - `sha256` — optional override; blank uses `release-sha256.txt`
5. The workflow downloads the master ZIP, verifies SHA-256, extracts the current distributables, generates `SHA256SUMS.txt`, and creates or updates the GitHub Release.

`release-source.txt` is intentionally not tracked. Do not commit temporary Dropbox URLs, signed URLs, credentials, tokens, or other private download locations.
