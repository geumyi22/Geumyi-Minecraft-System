# Day 12.6 — Release chain repository audit (2026-10-11 KST)

**Release-chain source review prepared; final Stable signing/publishing is BLOCKED.**

Previous successful CI covered GSC reproducibility, source secret scan, declared CycloneDX SBOM, System CI and synthetic DR. The actual Day12 final release workflow requires mandatory final JSON gates AND independent real health/security evidence, then safety/security/system/Android-signed/iOS builds. SHA256 sidecars are verified before manifest generation, signing and immutable-tag publication.

The new `tools/day12/audit_phase6_release_chain.py` verifies the source chain and real-byte manifest generator in an isolated temp directory. It checks fail-closed negative fixtures for 12.7, 12.10, 12.11, 12.12; mandatory native private-port and health/security evidence; signed Android requirement; Ed25519 manifest verification and release ordering.

**No actual Stable/Android/iOS build is signed or deployed by this audit**; no secret key or live system is accessed. The final release remains blocked by all unclosed mandatory live gates and 12.2 Lobby binary provenance. This is a *repository-ci* closure only, not a real signed release PASS.
