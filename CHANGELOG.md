# Changelog

## 2026-09-27 — Recovery completion and Day-4 verification

- Completed GST 1.1.1 HOTFIX, StatusAgent 0.5.4, GeumyiTechnology 0.1.3 and GeumyiChemistry 0.4.1 source recovery/reconstruction tracking.
- Captured sanitized live Wild/Playground server configuration evidence and completed Day-4 E2E verification.
- Kept runtime binaries in GitHub Releases rather than the source tree.
- Removed the unused `release-source.example.txt`; the release workflow uses the explicit `source_url` input plus `release-tag.txt` / `release-sha256.txt`.

## 2026-09-26 — Source recovery

- Expanded GSC 4.2.3, partial Agent 0.5.4, GSCM 1.1.2+112 and GDS 1.1.1 into their component directories.
- Expanded current Wild/Playground Java and Bedrock resource packs with original asset bytes.
- Replaced GSCM base64 archive with the real source tree; retained existing build steps and Android compatibility settings. Corrected iOS artifact label to 1.1.2.
- Recorded missing exact GST HOTFIX, Technology, Chemistry, Agent helper and server configuration sources explicitly.
- Excluded bundled executables/JARs/APKs/IPAs, old source/docs, missing-script launchers, runtime state and packaging duplicates.
- Replaced the private-looking QR-test address with a synthetic example; retained blank/placeholder-only configuration templates.
- Left existing release assets unchanged.
