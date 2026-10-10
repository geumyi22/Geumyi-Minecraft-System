# Day 12.2 — Cross-server binary fingerprint comparison (no new host scan)

**Evidence:** Previously supplied **real** operator report `Day12-Integrity-Security-20261009-061224.json` (2026-10-09 06:13:57 KST, `synthetic=false`, `phase=12.2+12.5`). This report is kept **private**; no jar SHA-256 values, machine paths, tokens, usernames or network addresses are committed. This review compares previously captured hashes; it does not authenticate any binary against a signed official release.

| Component | Target hosts | Existing matching files | SHA256 equality across expected non-Lobby targets | Exception or status |
|---|---|---:|---|---|
| GST 1.1.1 HOTFIX | wild, playground, other, lobby | 4/4 | **3/3 identical** (wild / playground / other) | Lobby has a documented deployment alias `GeumyiServerTools-1.1.1.jar` with a **different digest and size**; version-labelled alias is not hash-equivalent to HOTFIX. |
| GDS 1.1.1 | wild, playground, other, lobby | 4/4 | **3/3 identical** (wild / playground / other) | Lobby has documented alias `GeumyiDiscordStatus-1.1.1.jar` with **different digest and size**. |
| Technology 0.1.4 | wild, other | 2/2 | **2/2 identical** | Correctly not installed in playground or lobby. |
| Chemistry 0.4.1 | wild, other | 2/2 | **2/2 identical** | Correctly not installed in playground or lobby. |
| StatusAgent | host | expected 0.5.4 file found | **not a multi-host equality check** | Legacy 0.5.3 and 0.4.5 binaries were also inventoried at distinct candidate locations. Do not delete them from this observation. |

**2026-10-10 09:59 real one-click follow-up:** the canonical StatusAgent 0.5.4 filename appeared in the Java command line of **one** active process and **zero** Agent launch strings referred to other versions. This materially reduces the chance that a legacy JAR filename is the one launched. It is **not** a trusted digest or runtime loaded-class attestation. The first real one-click output's `active_agent_identity_is_proven=true` is **overstated**, and the source was fixed to separate filename observation from official artifact SHA verification.

## Required release-grade distinction

1. **Inter-host hash consistency** says multiple installed files have identical SHA-256 bytes. For GST and GDS on Wild/Playground/Other, this is useful and positive evidence of consistency.
2. **Lobby aliases differ**. Do not report all four hosts' binaries identical or rewrite/replace Lobby JARs with the other three servers' binaries based on name alone. Version metadata/ABI, actual plugin enable status and separately signed artifact provenance need confirmation; this is not an observed live failure.
3. **Release provenance** requires an official verified artifact digest or signed build manifest and in-place file digest comparison, not `deploy/components.json` filenames or this self-contained captured hash table. The 2026-10-09 report itself explicitly had `reference.trusted_hash_reference_available=false` and per-component `hash_authenticated_against_trusted_release=false`.
4. Real Java/Bedrock/Lobby route E2E belongs to **12.11**, offline known-good restart to **12.7**, and owner/bind attestation to **12.10**; none is implicitly cleared by 12.2 filename/hash equality.

**Current classification:** targeted file presence and groupwise equality positive; **12.2 final verified update provenance OPEN**, Stable BLOCKED. No live host write, JAR update/removal, backup mutation or rescan authorized.
