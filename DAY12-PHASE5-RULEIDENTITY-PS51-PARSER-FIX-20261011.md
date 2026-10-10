# Day 12.5 Local Rule Identity Triage — Windows PowerShell 5.1 parser fix (2026-10-11)

## Operator-reported defect
In `Day12_Phase5_Rule_Identity_Triage_READ_ONLY.ps1` from `Geumyi-Day12-Phase5-RuleIdentity-LocalOnly-READ-ONLY.zip`, the operator ran the CMD on the server PC. **[1/2] SelfTest failed at parse time**, before any host data was processed. Diagnostic showed Mojibake for Korean regex substrings on lines 23/27/28, causing unterminated string / unexpected token / unmatched `if` parentheses. The script was saved as UTF-8 **without BOM**, while Windows PowerShell 5.1 read its non-ASCII source using the system ANSI code page. This was a packaging defect, **not a firewall or GSC Host failure**.

## Fixed replacement, not a production policy change
Generated `Geumyi-Day12-Phase5-RuleIdentity-v2-PS51-FIX-READ-ONLY.zip` as conversation artifact, containing:
- Existing `Start_Day12_Phase5_Rule_Identity_Triage_READ_ONLY.cmd`, updated Windows 5.1 runner banner.
- `Day12_Phase5_Rule_Identity_Triage_READ_ONLY.ps1`: all source text ASCII except UTF-8 BOM; removes Hangul regex literals (Korean rule names may be grouped as `UNCLASSIFIED_NAME_ONLY`; that is not a risk verdict).
- Paired capture timestamp match of public/private local JSON within 120 seconds, count/ordered ordinal/profile/address-scope validation, fail-closed on mismatch.
- Local-only CSV formula prefix escaping; private identity names/IP/program strings **never** placed into the shareable JSON.
- `SHA256SUMS.txt`, README. **No firewall rescans, service/network/file ACL changes, Minecraft restarts or world/backup operations**.

## Validation distinction
- ZIP CRC and three SHA-256 entries match actual packaged bytes. Script starts with UTF-8 BOM, body contains only ASCII. Structural delimiter/string scan passed. Static command scan did not find firewall-mutation or host/network/service change commands.
- Current real operator redacted data: 38 broad candidates, Public-overlapping 15 ordinals `4,5,6,7,8,9,12,18,20,22,24,28,31,34,36`; other local-address-Any and non-Public: 21; local-address-restricted non-Public: 2. These are unchanged from the prior capture.
- **Windows PowerShell 5.1 interpreter self-test / full-run result remains NOT EXECUTED** for v2 at authoring time; static validation cannot be described as real runtime PASS. The operator should use only the new v2 extracted folder and report the result.

## Safety and release
Existing `DAY12-PHASE5-DECISION-SHARE-ONLY-THIS.json` and `PRIVATE-FIREWALL-RULE-IDENTITIES-DO-NOT-SHARE.json` stay local to operator PC. Never upload the private input or local identity CSV. `12.5` security final decision still OPEN; canonical backend port and Stable/Maintenance gates unchanged. No production changes or release promotion.
