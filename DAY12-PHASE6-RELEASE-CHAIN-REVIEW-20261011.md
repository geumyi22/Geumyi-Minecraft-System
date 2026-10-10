# Day 12.6 — Release chain repository audit (2026-10-11 KST)

**Release-chain source review prepared; final Stable signing/publishing is BLOCKED.**

Previous successful CI covered GSC reproducibility, source secret scan, declared CycloneDX SBOM, System CI and synthetic DR. The actual Day12 final release workflow requires mandatory final JSON gates AND independent real health/security evidence, then safety/security/system/Android-signed/iOS builds. SHA256 sidecars are verified before manifest generation, signing and immutable-tag publication.

The new `tools/day12/audit_phase6_release_chain.py` verifies the source chain and real-byte manifest generator in an isolated temp directory. It checks fail-closed negative fixtures for 12.7, 12.10, 12.11, 12.12; mandatory native private-port and health/security evidence; signed Android requirement; Ed25519 manifest verification and release ordering.

**No actual Stable/Android/iOS build is signed or deployed by this audit**; no secret key or live system is accessed. The final release remains blocked by all unclosed mandatory live gates and 12.2 Lobby binary provenance. This is a *repository-ci* closure only, not a real signed release PASS.

## CI result and evidence-ledger contract repair

[Day12 Phase6 Release Chain Source Audit run 38066005282](https://github.com/geumyi22/Geumyi-Minecraft-System/actions/runs/38066005282) completed **SUCCESS**. It ran the actual fail-closed source audit with synthetic negative gate cases and the real-byte manifest generator temporary fixture. No production signing or publication occurred.

The original `deploy/day12-scoped-evidence-ledger.json` CI enforces an exact set of **14** previously established closed-scope evidence IDs. Phase review outcomes for 12.9 / 12.2 / 12.6 were initially added to that protected array, causing a `CLOSED_SCOPED_EVIDENCE_KEYS_WRONG` source validation error. They are now moved to the separate `phase_review_decisions` section, **without weakening or expanding the fixed pass list**. An audit success can therefore coexist with the unchanged final Stable block.
