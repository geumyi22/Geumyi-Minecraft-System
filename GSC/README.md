# GSC 4.5.1 / StatusAgent 0.5.4

- [ServerCenter](ServerCenter/): current GSC 4.5.1 Go source, web UI, Host/Client split, installer templates, tests and build scripts.
- [StatusAgent](StatusAgent/): StatusAgent 0.5.4 source/recovery material.

## Day 11 verified live baseline (historical)

- GSC Host: **4.3.8 live**
- remote/local GSC Client: **4.3.8 live**
- Client-only and Host self-update paths: **user-confirmed LIVE PASS**
- Protection & Recovery 2.0: **LIVE PASS**
- Final integrated READ-ONLY E2E: **PASS**
- paired GSCM baseline: **1.1.5+117**

Historical recovery limitations and exact provenance remain documented in the component BUILD/RECOVERY files and `VERSION-MATRIX.md`. Do not remove recovery evidence merely because the runtime version has advanced.

## 2026-10-11 수동 설치 Stable 공개

[Windows GSC 4.5.1 Setup/Host/Client](https://github.com/geumyi22/Geumyi-Minecraft-System/releases/tag/system-2026.10.11-stable-gsc450-gscm150)는 CI 및 체크섬 검증 후 공개됐습니다. 실제 운영 설치 확인 버전은 여전히 **4.3.8**이며, 새 설치·실기기 E2E는 별도로 확인해야 합니다. 서명 자동 Stable 배포 명세는 발행하지 않았습니다.
