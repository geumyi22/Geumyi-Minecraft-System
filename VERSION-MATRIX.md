# Version Matrix

Baseline date: **2026-09-26**

| Area | Current | Scope |
|---|---:|---|
| Paper | 26.3 | Wild + Playground |
| GSC | 4.2.3 | Main PC / Server PC / Both |
| StatusAgent | 0.5.4 | Server management |
| GSCM | 1.1.2+112 | Android + iOS |
| GST | 1.1.1 HOTFIX | Wild + Playground |
| GDS | 1.1.1 | Wild + Playground |
| Technology | 0.1.3 | Wild only |
| Chemistry | 0.4.1 | Wild only |

## GSCM build outputs

- Android APK: GSCM 1.1.2 successful GitHub Actions build, run `36227422769`.
- iOS IPA: unsigned, internal version `1.1.2`, build `112`, bundle id `com.geumyi.gscm`.

## Current package layout

The maintained MC package uses:

- `야생 섭/`
- `놀이터 섭/`
- `금이 섭 관리/플러그인 최신본/`
- `금이 섭 관리/build/`

Inside `금이 섭 관리/build/`:
- latest unsigned IPA
- latest Android Builder CLEAN ZIP

No obsolete 26.2 rollback package is part of the current baseline.
