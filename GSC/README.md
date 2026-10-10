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

[Windows GSC 4.5.1 Setup/Host/Client](https://github.com/geumyi22/Geumyi-Minecraft-System/releases/tag/system-2026.10.11-stable-gsc451-gscm151)는 CI 및 체크섬 검증 후 공개됐습니다. 실제 운영 설치 확인 버전은 여전히 **4.3.8**이며, 새 설치·실기기 E2E는 별도로 확인해야 합니다. 서명 자동 Stable 배포 명세는 발행하지 않았습니다.

## GSC 4.5.1에서 달라진 점

- ViaVersion/ViaBackwards **Staging은 실제 적용이 아닙니다.** 등록된 Paper 서버가 모두 OFFLINE인 경우에만 별도 오프라인 적용을 명시적으로 실행하고, 백업·해시 확인 후 JAR 교체를 시도합니다.
- 적용 중 파일 교체에 실패하면 백업으로 복원을 시도합니다. 서버를 켠 뒤 플러그인 로드 실패까지 자동 롤백하는 것은 아닙니다. 실제 접속 및 호환성 검증이 필요합니다.
- 자동 GSC Host/Client Stable 업데이트용 **서명된 배포 manifest는 미발행**. 최신 패키지는 위 링크에서 수동 설치합니다. 마지막 실기기 설치 검증은 4.3.8입니다.
