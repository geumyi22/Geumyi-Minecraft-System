# GSC 5.2.0 빌드

GSC Host·Client·Setup은 Go로 빌드합니다. GSC Client에서 여는 Windows용 GMS Operating Mode 3.0.1은 같은 릴리스의 독립 실행 파일로도 제공됩니다. Windows x64 환경에서 빌드하며, Go 버전은 `go.mod`와 `.github/workflows/system-ci.yml`의 설정을 따르세요.

## 입력 파일

Setup은 `cmd/setup/payload/`에 아래의 런타임 파일이 필요합니다. GitHub System CI는 StatusAgent·GDS·GST 각 빌드 작업에서 검증된 파일을 받습니다. 수동 빌드는 저장소에 기록된 같은 버전과 출처의 JAR을 준비하세요. [기존 배포 자료](https://github.com/geumyi22/Geumyi-Minecraft-System/releases/tag/mc-2026.09.26-v3)

- `GeumyiStatusAgent-0.5.4.jar`
- `GeumyiServerTools-1.1.1-SpigotPaper26.3-GSCv4.1-HOTFIX.jar`
- `GeumyiDiscordStatus-1.1.1-SpigotPaper26.3.jar`

Host에는 `cmd/host/assets/gsc-velocity-control.jar`가 임베드됩니다. 이 플러그인을 다시 빌드할 때는 `Plugins/GSCVelocityControl/build.ps1`과 해당 README를 따르세요. JDK 25 이상에서 Java 17 바이트코드를 생성합니다.

## 빌드 및 시험

`GSC/ServerCenter`에서 실행합니다.

```powershell
.\build.ps1
go test ./...
go vet ./...
```

Go의 경로를 직접 지정하려면 `-Go 'C:\경로\go.exe'`를 전달하세요. Setup의 최종 출력은 `dist/GeumyiServerCenter-v5.2.0-Setup.exe`입니다. Setup 설치 안내는 `cmd/setup/payload/README-v5.2.0.txt`에 있습니다.

실제 PE 페이로드 추출과 파일 롤백 회귀는 빌드 후 테스트 환경에서 `GSC5_REAL_PAYLOAD_TEST=1`을 지정해 수행합니다. Windows 서비스·설치기 E2E는 일회용 Windows CI 러너에서 실행합니다. 운영 PC에 Setup을 실행하면 서비스와 프로그램, 자동 시작 설정을 변경할 수 있습니다.

## 릴리스

5.2.0 개인용 Stable 워크플로가 정확한 릴리스 커밋으로 Windows 빌드·회귀 시험을 수행합니다. 배포 키로 서명한 메타데이터와 업로드한 Draft의 파일 해시를 재검증한 후 공개합니다. [사용 방법과 업그레이드 범위](../../docs/releases/GSC-5.2.0-STABLE.md)
