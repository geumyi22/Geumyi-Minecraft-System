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

## 2026-10-11 — GSC 4.5.1 서명된 Beta 업데이트 게시

- [GSC 4.5.1 Beta 업데이트 릴리즈](https://github.com/geumyi22/Geumyi-Minecraft-System/releases/tag/system-2026.10.11-gsc451-signed-beta.1)에 `deployment-beta.json`, Ed25519 서명 `.sig`, 확인용 공개키와 Windows Setup 파일을 게시했습니다. [서명 및 공개 CI](https://github.com/geumyi22/Geumyi-Minecraft-System/actions/runs/38089609727) SUCCESS.
- 기존 Day 11 서명 Beta 릴리즈와 **동일한 Ed25519 공개키**를 확인하고, 기존 GSC Setup 패키지 SHA-256이 GitHub 원본과 일치함을 검증했습니다.
- 기존 GSC Host의 업데이트 채널이 **Beta**로 설정되어 있고 같은 공개키가 고정돼 있으면 4.5.1 신규 후보가 표시됩니다. Host와 Client의 적용은 사용자의 별도 승인 및 실기기 검증이 필요하며 즉시 자동 설치되는 것은 아닙니다.
- 이 Beta manifest의 구성요소는 `gsc` 하나뿐입니다. 기존 플러그인/서버 데이터의 자동 교체 대상은 없습니다. **Stable 채널의 `deployment-stable.json`은 여전히 미발행**입니다.

## GSC 릴리즈 채널 정책 (Draft)

- **Stable · 안정 운영**: 정식 서버·일반 PC, 명시 승인된 배포본만. 신규 설치 기본 선택값이며 업데이트 기능은 기본 **OFF**.
- **Beta · 사전 시험**: 보조 PC에서 정식 출시 전 기능/호환성 검증, 명시적 선택.
- **Canary · 개발 실험**: 격리 테스트 대상, 가장 높은 변경 위험, 명시적 선택.
- **기존 설정 보존**: 이전에 Beta/Canary를 선택했다면 업데이트만으로 채널을 임의 변경하지 않음.
- **서명된 manifest와 수동 설치 Stable은 별개**: GitHub Release의 이름만으로 서명 자동 Stable 배포가 가능해지는 것은 아님.
- GSC Host/Client 자체 업데이트와 Paper 서버 플러그인 업데이트 정책(managed/manual/hold/pin)은 별개이며 채널 선택만으로 설치나 재시작을 하지 않음.

세부 승격/롤백 기준: [GSC RELEASE CHANNEL POLICY](../docs/operations/GSC-RELEASE-CHANNEL-POLICY.md).

**이 개편은 Draft PR 검토 단계**이며 현재 설치된 GSC나 서명된 Stable 릴리스를 자동 갱신하지 않습니다.
