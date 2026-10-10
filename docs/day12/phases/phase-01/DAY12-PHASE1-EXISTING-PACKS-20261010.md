# Day 12.1 — existing Wild / Playground packs, reference-only

**Updated 2026-10-10 KST. Scope:** 4 operator-uploaded files checked locally in a sandbox, plus **Dropbox filename search only** for Java resource-pack storage. No running Host changes, world changes, pack installation/removal, GSC manifest activation or Golden backup operations.

**Important:** The operator already confirmed Wild and Playground **have applied packs**. The earlier optional `deploy/day12-managed-content.json` has zero **GSC-managed** active entries; this **does not indicate the servers have no packs**. The assignments in this document describe the operator's intended mapping for the uploaded reference bytes; a *matching on-host file hash or actual client-received version* has **not** been newly attested.

## Attachment-to-server assignment

| Index | Server | File / role | Offline file checks |
|---|---|---|---|
| **1** | **Playground** | `Geumyi_Server_Bedrock_26.50(1).mcpack`: Bedrock resource pack, v**1.0.2**, min engine **1.21.0** | ZIP CRC clean, 50 members, **33 custom OGG files ↔ 33 sound references**, no missing references |
| **2** | **Wild** | `Geumyi_Wild_Bedrock_BACAP_Korean.mcpack`: BACAP Korean Bedrock language pack v**1.0.1**, min engine **1.21.0** | ZIP CRC clean, `texts/ko_KR.lang` and `en_US.lang` available; **3,618** key/value-like entries each |
| **3** | **Wild** | `Geumyi_Wild_Bedrock_ChemTech.mcpack`: ChemTech Bedrock resources v**0.4.1**, min engine **1.20.0** | ZIP CRC clean, atlas with **222** item texture definitions and all **222** referenced PNGs present |
| **4** | **Wild** | `Geumyi_Wild_Geyser_CustomItem_Mappings.json`: Geyser custom item mapping definitions | JSON parses; **48** vanilla item groups, **212** unique Bedrock custom item IDs (**199 Chem + 13 Tech**); **all 212 icon names exist** in pack 3 atlas |

All three `.mcpack` files contain distinct header UUIDs and no ZIP path traversal entries. Pack 3 has **10 additional atlas icon definitions not referenced** by mapping 4 (machines/workstations); this is not inherently a defect. The manifest for pack 3 still describes **Chemistry 0.4.0 + Technology 0.1.0** despite pack version 0.4.1 and the frozen project target being Chemistry 0.4.1 / Technology 0.1.4: this is **possibly stale descriptive metadata**, not proof that the textures are incompatible. **Never update the pack header/version automatically based on that discrepancy.**

**BACAP risk:** The pack's own README states that localized text appears only if Geyser delivers matching translation keys. Its translated files may exist and still not translate advancements in-game; test with a **Korean-language Bedrock client** in Day 12.11.

**Geyser path risk:** pack 1 README advises `plugins/Geyser-Spigot/packs/`; this project has also used Velocity/Geyser. Do not infer the running server's current pack directory or redeploy based solely on an archived README. The live Geyser mapping load and item appearance require separate runtime evidence.

## Java packs — Dropbox inventory (private links not republished)

Read-only Dropbox filename search found these distinct files, whose byte contents and currently active server URLs were **not fetched/verified** in this review:

| Server candidate | Dropbox filename | Observed bytes | Candidate meaning |
|---|---|---:|---|
| Playground | `Geumyi_Server_Java_26.3.zip` | 12,961,843 | newer filename variant |
| Wild | `Geumyi_Wild_Java_26.3_BACAP_ChemTech.zip` | 3,455,608 | newer filename variant |
| Playground | `Geumyi_Server_Java_26.2.zip` | 12,978,309 | older filename variant |
| Wild | `Geumyi_Wild_Java_26.2_BACAP_ChemTech.zip` | 3,455,594 | older filename variant |

**No direct Dropbox preview/shared URL** is placed in the public GitHub repo. Because these names contain both 26.2 and 26.3 versions, **the active URL cannot be inferred merely from filename**. An existing server.properties `resource-pack`/SHA1 setting or another existing GSC configuration must be matched to a source file before any future opt-in management. The Dropbox account was searched read-only and no shared links were created or changed.

## Stable evidence boundary

`deploy/day12-existing-pack-reference.json` records non-secret local attachment SHA-256 values, header UUIDs/versions, expected server roles, texture-to-mapping reference checks, Java Dropbox filenames and explicit `no_automatic_pack_download` / `no_auto_adopt_existing_packs` safety policies. **The actual uploaded .mcpack binary files and mapping JSON are not pushed to GitHub**; if retention or sharing is desired, the operator must explicitly authorize it.

**12.1 outcome:** `REFERENCE_FILES_STRUCTURALLY_CHECKED + PREEXISTING_LIVE_PACKS_OPERATOR_CONFIRMED`; not `NO_PACKS`, not `PACK_APPLICATION_E2E_PASS`, and not `GSC_MANAGED_CONTENT_CONFIGURED`. Actual client pack receipt/mapping functionality, which specific variant is in use, and safe optional managed-content adoption remain open for Day12.11 or separately approved work. The four Golden protected backups and running worlds remain untouched.


## Existing Dropbox sharing (read-only check; links deliberately private)

After the operator pointed out that the **Java resource-pack links reside in Dropbox**, inspected the existing `list_shared_links` metadata **without creating or changing any share**:
- Playground `Geumyi_Server_Java_26.3.zip`: one existing public view link, downloads allowed.
- Wild `Geumyi_Wild_Java_26.3_BACAP_ChemTech.zip`: one existing public view link, downloads allowed.
- Playground older `Geumyi_Server_Java_26.2.zip`: one existing public view link, downloads allowed.
- Wild older `Geumyi_Wild_Java_26.2_BACAP_ChemTech.zip`: **no direct owned share link found** (could have other access arrangements; do not claim unreachable).

**No share URL or token is committed**. An existing Dropbox link proves a share exists on that account, **not** which exact URL is in the live `server.properties`, whether Minecraft downloads the pack today, or whether clients accepted it. Do not change any link or force-update existing applied packs. This closes the narrow "does Dropbox hold existing Java pack links?" question but preserves actual Java/Bedrock client 12.11 E2E.
