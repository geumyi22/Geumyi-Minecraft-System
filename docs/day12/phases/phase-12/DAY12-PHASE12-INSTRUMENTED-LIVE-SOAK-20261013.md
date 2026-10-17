# Day 12.12 — Actual host 8-hour instrumented soak evidence (2026-10-13)

**Operator-supplied actual server-PC counts-only JSON reviewed 2026-10-13 KST**  
Original filename: `DAY12-SOAK-SUMMARY-SHARE-ONLY-THIS.json`  
Original uploaded bytes SHA-256: `5e2768341791ef9ca408c260ed86498f848eebe5ac2231d62ffdf6b00cad057a`  
**Source JSON is not checked into GitHub.** In particular `PRIVATE-SAMPLES-DO-NOT-UPLOAD.ndjson` must remain private.

## Observed result and exact scope

| Field from the host JSON | Value |
|---|---|
| `schema` / `phase` / `mode` | `3` / `12.12` / `CONTINUOUS_READ_ONLY_SOAK` |
| `read_only` / `production_mutation` | `true` / `false` |
| Captured start/end (UTC) | `2026-10-12T16:35:56.3028631Z` — `2026-10-13T00:35:57.7237171Z` |
| Captured start/end (Asia/Seoul) | **2026-10-13 01:35:56 — 09:35:57 KST** |
| Duration target / monotonic observed | 8 h / **8 h** |
| `duration_requirement_met` | `true` |
| Sample interval / total samples | **5 min / 97 samples** |
| Maximum gap / `sampling_continuity_adequate` | **5 min / true** |
| Observed java/GSC process identities added/removed | **0 / 0** |
| Identity unverifiable pairs | **0** |
| `observed_process_identity_stable` | `true` |
| `application_probe_unhealthy_samples` | **0** |
| `capture_error_samples` | **0** |
| `result` / `stable_release_allowed` | `REVIEW_REQUIRED` / `false` |
| `bedrock_java_real_client_e2e_verified` | `false` |

**Review disposition:** **`PASS_REAL_HOST_INSTRUMENTED_8H_TCP_PROCESS_SCOPE`**. The requested real-host continuous eight-hour observation was actually collected and meets its duration, sampling continuity, basic loopback TCP control reachability and observed Java/GSC process-identity stability checks. There are **zero observed abnormalities in this sampling scope**. Operator no longer needs to restart or repeat a routine eight-hour soak merely because the first kit ran before the Other-aware update.

**Legacy kit / intentional Other OFFLINE:** The host ran the **older** operator ZIP, whose summary notes the four loopback TCP controls `25565/25566/25567/8787`. The operator separately confirms **Other Paper backend intentionally OFFLINE** at this time. These observations are compatible: `25567` is a **Velocity public/proxy FRONTEND** which can be listening even when the Other Paper BACKEND is OFFLINE. Therefore the zero unhealthies is not evidence that Other Paper was running, and its intentional shutdown is **not a crash**. No individual TCP control snapshot or sampled per-backend process status is provided in this sanitized summary. The newer Other-aware kit is not required to repeat this full eight-hour observation.

## Not established by this report

1. **The JSON itself says `REVIEW_REQUIRED` and `stable_release_allowed=false`**; manual review records a **scoped monitoring PASS**, not an automatic final Stable gate override.
2. TCP connect probes are limited to local control listeners; they do **not** prove real Java/Bedrock gameplay, RakNet, GSC authenticated application routes, or the Other backend state. Short outages under five minutes could have occurred between samples.
3. Observing **zero Java/GSC process churn** does not prove every intended Paper server was running, exact binary hashes, or every port's PID/address binding.
4. This evidence does not prove **12.5 actual non-admin Effective Access**, **12.10 native Java/RCON private listener ownership and bind**, **12.7 genuine offline startup on this operator host**, or **12.11 signed staging Canary apply/rollback**.
5. No production files, ACLs, firewall, worlds, backups, services or process lifecycle were changed by this read-only soak; data explicitly reports `production_mutation=false`. Do not infer end-to-end no-change assurance outside the scope of this monitor.

## Project disposition

- **12.12 monitoring subtest:** **PASS, real host, scoped**. This supersedes historical `OPERATOR_ACCEPTED_NO_TELEMETRY` as stronger, independently reviewable live observation evidence.
- **12.12 complete release gate:** **REVIEW / pending formal release-gate assessment**; no self-attested `FINAL-SOAK-REPORT.json` or `FINAL-RELEASE-GATES.json` promotion.
- **Other backend:** operator-intentional **OFFLINE**; do not turn on just to fabricate four running Paper endpoints.
- **Final signed Stable:** **BLOCKED** by independent security/native bind/offline boot/Canary validation and required closure decision. The already published **manual** GSC 4.5.1 / GSCM 1.5.1+151 Stable remains a distinct existing release.
- **PR #53:** Draft/unmerged until all required final evidence and change review legitimately pass.

Related: [Day 1–12 master](../../../PROJECT-DAY1-12-MASTER-STATUS-20261013.md), [Day 12 index](../../INDEX.md), [Stable fast-track](../../DAY12-STABLE-FAST-TRACK-20261013.md).
