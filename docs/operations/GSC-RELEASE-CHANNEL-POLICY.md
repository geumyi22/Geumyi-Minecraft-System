# GSC Release Channel Contract — Stable / Beta / Canary

**Scope:** GSC Host/Client release selection and GSC Update Center signed deployment manifests. The Paper/Velocity/Minecraft runtime remains separate; changing channel does not itself restart or modify any service. This policy is staged in Draft PR #53 only; no production settings or GitHub release are altered.

## Channel definitions

| Channel | Audience & purpose | Admission and publication | Installation and rollback |
| --- | --- | --- | --- |
| **Stable (안정)** | Production host, regular admin clients; reliable everyday use | Build/tests PASS, security/signature/checksum verification, rollback readiness, representative Beta operational smoke/E2E and explicit operator promotion approval. Block while any required Stable release gate is unmet. | Default for **new configurations** with updater OFF; stage only authenticated, signed `deployment-stable.json`. Separate explicit approval to apply Host/Client; safeguard Minecraft state. |
| **Beta (시험)** | Secondary PC, selected testers; release candidates, compatibility and UX validation | CI, installer/integrity/signature tests pass, targeted regression/smoke checks pass; documented known issues and rollback path; human approval to publish. | Explicit opt-in; signed `deployment-beta.json`, no silent roll-up into Stable. Collect diagnostic results; on blocking regression hold candidate and revert affected test target. |
| **Canary (개발)** | Isolated development/test environment only; shortest feedback for new changes | Build, static/security checks, basic synthetic tests, signed and traceable manifest if published; may be draft/unpublished and thus undiscoverable. No promise of general operability. | Explicit opt-in, ideally pin exact tag, prefer manual + test machine; immediate stop on failure. Does **not** imply Beta/Stable readiness. |

## Explicit distinction: GSC release vs deployment manifest

- A GitHub Release labeled `Stable` that contains a Windows setup installer is **not automatically eligible for GSC self-update**. A **published**, correctly signed, trusted-key-verified `deployment-stable.json` + `.sig` and matching artifact SHA-256 are additionally required.
- Beta/Canary manifests MUST NOT be treated as Stable merely because version numbers are newer or the release appears in GitHub Releases.
- GitHub Draft, CI artifact or local RC is **not** a published update. No auto-discovery or Stable promotion from a draft.
- The signing public key must be pre-trusted and independently configured. Never trust a key downloaded alongside the release without prior pinning.
- Selecting a channel is **selection of candidate source, not update approval**; the current updater/Host–Client flows retain their independent stage/apply confirmation and existing player-aware or service-specific restart controls.
- GSC self-update (Client PC / Host PC) is distinct from **per-Paper-server plugin update policy** (`managed`, `manual`, `hold`, `pin` and `inherit` channel). The UI must label both clearly. The same signed manifest feed may contain components scoped to individual targets; no automatic Paper/Velocity update is authorized by changing GSC channel.
- **GSCM (Android/iOS)** and external components (Velocity, Geyser, Paper, plugins) have their own release/installation requirements; GSC's channel selection cannot change them implicitly.

## Promotion / rollback contract

1. **Canary → Beta**: source/build provenance and checksum, passing CI and functional tests, documented known issues, safe upgrade and downgrade plan, a tested disposable or secondary-PC scenario; explicit approval.
2. **Beta → Stable**: release candidate freeze, operator smoke + representative device and server E2E, security/access and update signature proof, last-known-good + tested rollback, release gates clear, explicit production release approval. No inference from GitHub tag text or elapsed time.
3. A candidate rejected at any gate stays in its current channel or draft. No automatic channel promotion.
4. A bad release requires suspending that channel candidate, marking affected targets HOLD, using verified last-known-good **only with explicit approval**. Old server worlds/plugins cannot be overwritten by a GSC client downgrade.
5. Switching Stable → Beta/Canary on an operating installation demands deliberate human confirmation; no automatic apply or service restart. Moving Beta/Canary → Stable likewise only changes release selection until separate installation approval.
6. Security fixes follow the same integrity/signature gate; emergency exceptions require documented scope, owner, rollback and explicit authorization (not silent Stable promotion).

## Existing configuration & compatibility

- For **new installs** and unsupported/empty configuration values: updater remains `enabled=false`, channel defaults to `stable`.
- For **existing installations** explicitly configured to `beta` or `canary`, preserve that selection on upgrade. No automatic migration, no installation or restart as a side effect.
- Existing per-server explicit channel override/pin/hold policies are untouched; `inherit` uses the global selection.
- Signed-channel manifests are isolated: `deployment-stable.json`, `deployment-beta.json`, `deployment-canary.json`, each with its own signature and strict channel match. A higher-version candidate in a different channel must not be substituted.

## Evidence boundaries as of 2026-10-17

- GSC 4.5.1 **manual install Stable** GitHub Release is documented; this is **not** proof that automatic signed Stable manifest has been published or that a live Host/Client was upgraded.
- GSC 4.5.1 **signed Beta** release has separate manifest/signature according to the repository README; that does not imply Stable promotion.
- The latest verified operator P0 backup/isolated restore results support *settings backup recoverability*, not a complete P1 worlds/plugins backup, production upgrade E2E or permission to publish signed Stable.
- **Release gate remains blocked** for the Day12 Draft hardening work. Do not change `FINAL-RELEASE-GATES.json`, PR Draft status, running host configurations, stable tags or releases as part of this policy proposal.

## Operator-friendly labels

- **Stable · 안정 운영** — 가장 안전한 권장 채널. 검증 완료 및 승인된 정식 버전만.
- **Beta · 사전 시험** — 새 기능을 먼저 시험. 문제·되돌리기 가능성을 이해하고 선택.
- **Canary · 개발 실험** — 오류 가능성이 가장 높음. 메인 서버 PC에는 비권장.
- Channel switch is **not** itself a download, installation, restart or sign-off.

