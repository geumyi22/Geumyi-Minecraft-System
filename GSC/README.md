# GSC 4.5.0 / StatusAgent 0.5.4

- [ServerCenter](ServerCenter/): current GSC 4.5.0 Go source, web UI, Host/Client split, installer templates, tests and build scripts.
- [StatusAgent](StatusAgent/): StatusAgent 0.5.4 source/recovery material.

## Day 11 verified live baseline (historical)

- GSC Host: **4.3.8 live**
- remote/local GSC Client: **4.3.8 live**
- Client-only and Host self-update paths: **user-confirmed LIVE PASS**
- Protection & Recovery 2.0: **LIVE PASS**
- Final integrated READ-ONLY E2E: **PASS**
- paired GSCM baseline: **1.1.5+117**

Historical recovery limitations and exact provenance remain documented in the component BUILD/RECOVERY files and `VERSION-MATRIX.md`. Do not remove recovery evidence merely because the runtime version has advanced.

## 2026-10-11 source version bump

GSC 4.5.0 Host, Client and Setup are release build targets. Historical 4.3.8 is last actual installed Host/Client confirmed by the operator; version bump alone is not proof of installed 4.5.0.
