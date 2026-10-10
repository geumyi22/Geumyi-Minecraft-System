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


## 2026-10-10 — actual Day-11 GitHub CI artifact-bytes compared to previously captured installed hashes

We retrieved the **actual ZIP artifact bytes** (not just GitHub artifact metadata) from:
- [Day-11 Secure Release build `37627140918`](https://github.com/geumyi22/Geumyi-Minecraft-System/actions/runs/37627140918): artifact IDs `11484034230` (StatusAgent), `11484433267` (GST HOTFIX), `11484547251` (GDS), `11485305843` (Technology), `11485250161` (Chemistry).
- [Day-11 System CI `37617403835`](https://github.com/geumyi22/Geumyi-Minecraft-System/actions/runs/37617403835): second reference artifacts `11480851827` (GST HOTFIX), `11480696839` (GDS), `11480158001` (Technology), `11480092953` (Chemistry).

For each Secure Release artifact ZIP the contained `.jar.sha256` sidecar agrees with the SHA-256 computed independently from its actual archived JAR. The comparison to the **real 2026-10-09 06:13 server-PC report** used the full SHA-256 value, not partial-prefix equality. No user-machine binary or secrets were uploaded or modified.

| Target | Installed JAR vs Secure Release artifact content | Against original Day-11 System CI |
|---|---|---|
| StatusAgent **0.5.4**, canonical installed file | **SHA256 MATCH** and size match (58,722 B). Older 0.5.3 and 0.4.5 files are separate, expected nonmatches. | Not required for this confirmed matching release artifact. |
| Technology **0.1.4** — Wild + Other | **SHA256 MATCH** on both servers, size 53,212 B | **MATCH** against original CI as well |
| GST **1.1.1 HOTFIX** — Wild + Playground + Other | **DIFFERENT SHA256 AND SIZE** vs packaged CI artifact, which contains a 94,488 B JAR; the installed file was 93,988 B | **DIFFERENT** |
| GST Lobby alias | **DIFFERENT SHA256** even though both have size 94,488 B | **DIFFERENT** |
| GDS **1.1.1** — Wild + Playground + Other | **DIFFERENT SHA256 AND SIZE**; CI artifact 77,662 B vs installed 77,650 B | **DIFFERENT** |
| GDS Lobby alias | **DIFFERENT SHA256** at same 77,662 B size | **DIFFERENT** |
| Chemistry **0.4.1** — Wild + Other | **DIFFERENT SHA256 AND SIZE**; CI artifact 60,375 B vs installed 55,857 B | **DIFFERENT** |

**Decision:** Two components now have **real CI-artifact byte-match evidence** (StatusAgent 0.5.4 and Technology 0.1.4) and this resolves *their* previously open official-build-digest question, as far as the selected CI build identity and historical capture go. **GST, GDS and Chemistry remain DIVERGENT_FROM_TWO_SELECTED_DAY11_CI_BUILDS, not automatically compromised or broken.** Version strings alone do not show which exact build was intentionally deployed; unknown older or custom build provenance requires locating the actual deployment manifest/CI run or a separately approved update plan. Even the two digest matches don't demonstrate plugin enabled/live function on all clients; E2E gates remain separate.

**Do not** hot-swap GST/GDS/Chemistry, delete original/legacy JARs or mark 12.2 entirely PASS based on these comparisons. The existing 12.0 Golden 4/4 is the rollback boundary if an eventual change is approved. This note carries only redacted equality/size facts, not full original operator hashes or machine paths.
