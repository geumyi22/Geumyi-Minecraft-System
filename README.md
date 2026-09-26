# Geumyi Minecraft System

최신 확정 기준의 실제 원본을 모은 저장소입니다. **복구가 끝난 소스와 아직 없는 소스를 아래 표에 구분했습니다. 전체 구성요소의 소스 복구가 완료된 상태는 아닙니다.**

| Component | Baseline | Path | Recovery status |
|---|---|---|---|
| GSC | 4.2.3 | GSC/ServerCenter | Recovered source; installer JAR payloads supplied from Releases |
| GeumyiStatusAgent | 0.5.4 | GSC/StatusAgent | Partial overlay (4 Java files); helper source not yet recovered |
| GSCM | 1.1.2+112 | GSCM | Recovered Flutter/Android source and iOS generation scripts |
| GST | 1.1.1 HOTFIX | Plugins/GeumyiServerTools | source not yet recovered for exact HOTFIX |
| GDS | 1.1.1 | Plugins/GeumyiDiscordStatus | Recovered full plugin source, stubs and tests |
| GeumyiTechnology | 0.1.3 | Plugins/GeumyiTechnology | source not yet recovered |
| GeumyiChemistry | 0.4.1 | Plugins/GeumyiChemistry | source not yet recovered |
| Wild server | Paper 26.3 | Servers/Wild | Paper provenance recovered; current operational configuration source not yet recovered |
| Playground server | Paper 26.3 | Servers/Playground | Paper provenance recovered; current operational configuration source not yet recovered |
| Resource packs | Java 26.3 / bundled Bedrock | ResourcePacks | Recovered expanded assets and Wild Geyser mapping |

## 사용 방법

- GSC: [빌드 안내](GSC/ServerCenter/BUILD.md). 설치기용 JAR은 기존 Release에서 가져와 로컬에만 둡니다.
- GSCM: [빌드 안내](GSCM/BUILD.md). Android/iOS Actions는 GSCM/의 실제 파일에서 빌드합니다.
- GDS: [빌드 안내](Plugins/GeumyiDiscordStatus/BUILD.md). 기본 config.yml에는 실제 비밀값이 없습니다.
- 리소스팩: [구성 및 패키징](ResourcePacks/README.md). Java/Bedrock 팩의 필수 이미지·사운드 원본을 포함합니다.

완성 EXE/JAR/APK/IPA/ZIP은 [기존 Release](https://github.com/geumyi22/Geumyi-Minecraft-System/releases/tag/mc-2026.09.26-v3)에 유지합니다. 운영 설정·토큰·키스토어·월드·로그는 Git에 넣지 않습니다. 구버전 소스를 최신 버전으로 바꾸어 표시하거나 JAR을 역컴파일해 원본처럼 등록하지 않았습니다.

자세한 근거는 [RECOVERY-REPORT.md](RECOVERY-REPORT.md), [SECURITY-NOTES.md](SECURITY-NOTES.md), [SOURCE-MANIFEST.json](SOURCE-MANIFEST.json)을 확인하세요.
