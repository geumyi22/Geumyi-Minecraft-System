# Day 7 — Component CI / automatic build foundation

Date: 2026-09-28  
Status: **COMPLETED**

## Scope

Day 7 establishes verified automatic build artifacts for the Geumyi-managed components. It does **not** automatically deploy those artifacts to the live Minecraft servers yet; secure release promotion and pre-start updating begin in Day 8.

## Final CI results

### System CI

Final successful run: **36448831023**

Passed jobs:

- GSC 4.2.3 — Windows `go test ./...`
- GeumyiStatusAgent 0.5.4 — JDK 21 clean build + artifact
- GDS 1.1.1 — JDK 21 build + CoreTests + artifact
- GST 1.1.1 HOTFIX — JDK 21 overlay build + CoreTests + artifact
- GeumyiTechnology 0.1.3 — JDK 25 / Gradle 9.1.0 build + artifact
- GeumyiChemistry 0.4.1 — JDK 25 / Gradle 9.1.0 build + artifact
- ResourcePacks — JSON / pack metadata validation
- GSC 4.2.3 CI Setup — automatically assembled after downloading the freshly built Agent/GDS/GST artifacts
- Day-7 summary — all required jobs reported `success`

The first expanded System CI run **36448477564** correctly failed Technology/Chemistry because their recovered Gradle files requested Paper 26.3 while forcing Java 21 dependency compatibility. Paper 26.3 advertises JVM 25 compatibility. Commit `1bbf421880a52d359a3121db8bff408099676f8f` aligned those two builds with Java 25; the next run passed.

### GSCM Android

Run: **36448477722** — **PASS**

- Flutter pinned to **3.47.5 stable**
- package resolution
- `flutter analyze`
- `flutter test`
- release APK build
- version-derived artifact naming
- checksum sidecar generated from inside the artifact directory

Artifact: `GSCM-1.1.2-build113-Android`

### GSCM iOS

Final clean packaging run: **36449571301** — **PASS**

- Flutter pinned to **3.47.5 stable**
- package resolution
- `flutter analyze`
- `flutter test`
- release no-codesign build
- unsigned IPA packaging
- temporary `Payload/` removed before artifact upload
- artifact contains only IPA + checksum sidecar

Artifact: `GSCM-1.1.2-build113-iOS-unsigned`

## Artifact verification

Downloaded CI artifacts were independently inspected after the Actions runs.

### Managed plugin / Agent artifacts

| Component | CI output SHA-256 | Class major |
|---|---|---:|
| GST 1.1.1 HOTFIX | `3e0e97afba7ac90ce1c97f4e3491d22b1076ef919928d7a8669898e995dd3c96` | 65 / Java 21 |
| GDS 1.1.1 | `efce23ec9fb2466d8ade90e38fa6e27998c502804dfb03f2e627fe2912f1e600` | 65 / Java 21 |
| StatusAgent 0.5.4 | `eb6b2f5cdff52bcebdb833fee34b846b07c81c42895ea71e5081824ba3a618ed` | 65 / Java 21 |
| Technology 0.1.3 | `6e1f2800a9b8d74e47f535311fe23cb35d9a10063f4923d3be79d0bc0be38f98` | 69 / Java 25 |
| Chemistry 0.4.1 | `25b902e0e84d92d953cca908387fd5c89d3d57d42f77a8d859dfc00eb0bf4284` | 69 / Java 25 |

All artifact ZIPs passed ZIP integrity checks and every included `.sha256` sidecar matched the corresponding binary.

Technology/Chemistry `plugin.yml` files in the produced JARs report the expected versions and Paper API `26.3`.

### GSC CI package

The GSC package was assembled only after fresh Agent/GDS/GST artifacts passed their jobs.

- Setup: `c6b90b054f2db615b9952787e2e13463cb50f414d10355ff3e3e14248e61add0`
- Client: `a9d3517313a2c6963c4d83ff70a0736f95348f7bb23c994fa65e1a65a0069cdb`
- Host: `c6d9ffe44b9e5011f89be7f53ca7f3f82aad74ce47946d2d397589bacaefffbe`

The packaged `SHA256SUMS.txt` matched all three binaries.

### GSCM artifacts

- Android APK: `0cbe1ba1d77e86c5c728389d0b98e1c959aae99543d9784ef0f2a0080c25aa7f`
- final clean iOS unsigned IPA: `980a0b2689c1f23998f7319af2d29af02d875ee00153be7126baca94d52a2b98`

The Android and final iOS checksum sidecars matched their binaries. The final iOS Actions artifact contains exactly two files: the IPA and its checksum.

## Build-system changes

- `.github/workflows/system-ci.yml` now covers GSC, Agent, GST, GDS, Technology, Chemistry and ResourcePacks.
- GSC Setup is assembled as a dependent CI job from freshly built Agent/GDS/GST artifacts.
- GST and GDS `build.sh` scripts execute their CoreTests before packaging.
- GST CI verifies the pinned deployed reference/core JAR SHA-256 before using it for the binary-only legacy core boundary.
- Technology/Chemistry build with JDK 25 + Gradle 9.1.0 for Paper 26.3.
- GSCM workflows are pinned to Flutter 3.47.5 and derive artifact names from `pubspec.yaml`.
- Android/iOS checksum files now use directly verifiable relative filenames.
- iOS temporary packaging contents are excluded from the uploaded artifact.
- workflows have source-path triggers so unrelated documentation changes do not rebuild components.

## Boundaries / Day-8 handoff

Day 7 proves **source/build/test/artifact generation**, not automatic production deployment.

Still intentionally pending:

- persistent Android release signing; current CI APK signer remains unsuitable for guaranteed in-place updates across runs
- Stable/Beta/Canary deployment manifests
- signed manifest/provenance
- Release promotion
- pre-start server updater
- live-server automatic JAR replacement
- rollback/health-gated deployment
- external-plugin update policy

CI output hashes are not asserted to equal the historical deployed Release hashes. Reconstructed sources, normal JAR/ZIP metadata and the StatusAgent/GST provenance boundary can produce different archive bytes. Day 7 verifies the current tracked source can produce structurally valid, tested artifacts.

## Result

**Day 7 completed.**

The repository now has the build foundation required for Day 8 secure Release and next-start automatic update work.
