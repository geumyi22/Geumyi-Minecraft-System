# GSC 5.1.0 빌드

GSC 5.1.0은 개인용 서버 관리 기능을 추가한 개발본입니다. Host·Client·Setup 제품 버전은 함께 맞추되, 공개된 5.0.0 릴리스 파일·서명·승인 기록은 유지합니다. 기존 v4 관리 API와 GSC 연동 기능도 유지합니다.

이번 기능 검증은 기존 운영 서버와 별도 폴더의 **개인용 Host/Client 패키지**로 수행했습니다. Setup의 소스 버전과 출력 이름을 맞춘 사실을 Setup 설치·역할 전환·운영 업데이트 검증 또는 공개 배포 완료로 해석하지 마세요.

## 필요한 파일

Windows에서 Go 1.23.2 이상 호환 환경을 사용합니다. 이번 개발 검증에는 Go 1.27.4를 사용했습니다.

Setup은 기존 연동 파일을 포함하므로 `cmd/setup/payload/`에 다음 파일이 필요합니다. 기존 [mc-2026.09.26-v3 릴리스](https://github.com/geumyi22/Geumyi-Minecraft-System/releases/tag/mc-2026.09.26-v3)의 해당 배포 파일을 사용합니다.

- `GeumyiStatusAgent-0.5.4.jar` — GSC FINAL archive / Agent bundle 안의 파일
- `GeumyiServerTools-1.1.1-SpigotPaper26.3-GSCv4.1-HOTFIX.jar`
- `GeumyiDiscordStatus-1.1.1-SpigotPaper26.3.jar`

이 연동 구성 요소의 버전은 GSC 제품 버전과 별개입니다. 5.1.0으로 이름을 바꾸지 마세요. Setup이 읽는 기존 템플릿 경로와 과거 버전 README도 유지합니다. 현행 설치 설명서는 `cmd/setup/payload/README-v5.1.0.txt`입니다.

Host에는 `cmd/host/assets/gsc-velocity-control.jar`가 임베드됩니다. 소스 패키지의 해당 자산을 포함해야 합니다. 플러그인을 수정하여 재빌드할 경우 저장소의 `Plugins/GSCVelocityControl/build.ps1`과 그 폴더의 README를 따르세요. 플러그인 빌드에는 JDK 25 이상이 필요하며 Java 17 바이트코드를 생성합니다.

## 빌드 순서

`GSC/ServerCenter`에서 다음 명령을 사용합니다.

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\build.ps1
```

`build.ps1`은 현재 소스로 Host·Client를 먼저 빌드하여 Setup payload에 넣고, 그다음 `dist/GeumyiServerCenter-v5.1.0-Setup.exe`를 생성합니다. 기존 EXE를 파일명만 바꾸어 새 버전으로 사용하지 마세요. Go 실행 파일을 직접 지정하려면 `-Go 'C:\경로\go.exe'`를 전달합니다.

```powershell
go test ./...
go vet ./...
```

테스트·빌드 성공과 실제 Setup 설치 성공은 별개입니다. 실제 Windows payload·롤백 검사는 빌드 후 `GSC5_REAL_PAYLOAD_TEST` 조건으로 실행되며, 운영 PC의 설치나 작업 스케줄러 조작을 대신 검증하지 않습니다.

## 실행 방식과 배포 구분

새 게임 서버 7종과 새 Velocity는 별도 프로필로 관리합니다. 기존 Velocity 3개는 Windows 작업 스케줄러 소유를 유지하고, 정상 종료 연결은 별도 제어 플러그인을 통해 준비합니다. 예전 직접 관리 실험을 운영 소유권 이관으로 복구한 것이 아닙니다.

기존 5.0.0 전용 배포 workflow·릴리스 노트·승인 ledger는 과거 공개 릴리스를 위한 기록입니다. 이 버전 번호 변경만으로 5.1.0 게시·자동 업데이트·서명을 수행하지 않습니다. 개인용 실행 패키지와 Setup 설치 방식도 구분해서 검증해야 합니다.

Setup의 생성된 payload EXE/JAR 및 설정·인증정보는 임의로 저장소에 추가하지 마세요. 소스에서 명시적으로 관리하는 Velocity 제어 플러그인 임베드 자산은 예외입니다.
