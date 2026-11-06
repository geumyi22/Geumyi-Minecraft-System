# GSC v5 post-Stable backlog (proposal, not implemented)
**2026-10-26.** No live server changes; no automatic opt-in. This backlog is deliberately **excluded** from GSC 5.0.0-beta.1 and the 5.0.0 Stable release gate.

| Target (tentative) | Feature | Minimum safe acceptance criteria |
| --- | --- | --- |
| 5.1 | AI-assisted incident diagnosis | Redacted logs/process/port evidence, deterministic rules first, model inference marked as hypothesis, no credentials uploaded, no execute privilege |
| 5.1 | Integrated topology dashboard | Explicit observed vs configured Paper/Velocity/Geyser/Agent edges, timestamps, offline/error/unknown distinctions; separate Other Paper OFF from Other proxy task Running |
| 5.2 | Smart recovery 2.0 | Per-service opt-in, bounded retries, crash vs deliberate shutdown distinction, player-aware window, single-owner locking, rollback and audit; no automatic Velocity takeover |
| 5.2 | Update simulation | Offline signed manifest/schema/dependency/compatibility/checksum/backup/rollback preflight; dry-run must never mutate services/worlds |
| 5.2 | GSCM mobile incident view | Authorized read-only alerts, duplicate suppression, offline/reconnect behavior, deliberate operator approval for potentially destructive actions |

## Architecture boundaries
1. Diagnose first: use source evidence (GSC Host logs, RCON results, Java/Paper state, network sockets) and explain **what is observed vs inferred**. A generative model never directly issues an OS command.
2. No silent access expansion: continue v4-compatible paired-device/auth model; collect only privacy-reviewed, minimum necessary logs. Never print credentials, Floodgate private keys, signing keys or full local user paths.
3. Read-only by default; if an operator explicitly enables future actions, use isolated capability permissions, expected-state checks, transaction journal, safeguards and a confirmed rollback path.
4. Do not reintroduce archived PR #55/#57/#58 direct Velocity lifecycle/cutover without a **new and separately authorized** design and real cutover/rollback proof. Existing Scheduler remains the owner.
5. Do not treat a mockup, green CI, or accepted proposal as deployed functionality. Each future feature needs unit, integration, security and real-device E2E evidence.

**First implementation after 5.0.0 Stable:** build an explainable rule-based diagnostic event format and read-only topology inventory. Add optional AI analysis only once redaction, audit and user-controlled data scope are verified.
