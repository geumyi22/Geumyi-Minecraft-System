# GMS Operating Mode 3.0.1 소스 빌드

Windows 11 x64의 64비트 Windows PowerShell에서 소스 ZIP의 압축을 풀고, 압축을 푼 디렉터리에서 실행합니다. 빌드는 Windows에 포함된 .NET Framework C# 컴파일러를 사용합니다. NuGet 패키지나 SDK 다운로드는 없습니다.

```powershell
.\build.ps1
.\build.ps1 -Test
.\qa-pe.ps1 -Executable .\bin\GMS_OperatingMode_v3.0.1.exe
.\qa-ui.ps1 -Executable .\bin\GMS_OperatingMode_v3.0.1.exe
```

로컬 정책이 PowerShell 스크립트를 제한하는 환경에서는 조직에서 승인한 실행 절차를 사용합니다. 배포 EXE를 열 때 빌드 스크립트를 실행할 필요는 없습니다.

## 구성

| 위치 | 내용 |
|---|---|
| `src/Program.cs`, `Dashboard.cs`, `app.manifest` | GUI 진입점, 일반 권한 조회, 같은 계정 UAC, 미리보기, 상태 및 오류 표시 |
| `src/Windows*.cs` | Windows 시작 항목의 식별·백업값 읽기·변경·복원 |
| `src/Transaction.cs` | 상태 모델, 관리자 복구 저장소, 전환·롤백·중복 방지 |
| `src/RuntimeOps.cs`, `LocalAssetPath.cs`, `LegacyWindow.cs` | 등록 경로·프로세스 조사, GSC 정상 종료와 수동 시작, 로컬 자산 판정, 이전 창 식별 |
| `tests/` | 격리된 레지스트리·시작 폴더, 메모리 작업 정의, 전환 중 장애, 현재 세션과 자식 모의 Host를 사용하는 시험 |
| `qa-preservation.ps1` | 대표 파일의 기준 해시 수집 및 재대조. 표본 경로와 파일 내용은 배포하지 않음 |

결과 EXE는 `bin/GMS_OperatingMode_v3.0.1.exe`입니다. `-Test`는 테스트 전용 실행 파일도 같은 폴더에 만듭니다. GUI 검사는 일반 권한의 인터랙티브 데스크톱에서 실행하며 같은 버전의 다른 창은 먼저 정상 종료합니다. 시험은 직접 시작한 프로세스만 정리합니다. Java 또는 구형 스크립트가 없는 개발 PC에서는 해당 실물 기반 사례가 건너뛰어질 수 있습니다. 이미 알려진 구형 스크립트가 수정돼 있다면 해당 양성 시험에서 차이가 나타날 수 있습니다.

배포 해시는 제공된 EXE에 해당합니다. Windows 기본 컴파일러는 다시 빌드하면 작성 시각 등으로 결과 해시가 달라질 수 있습니다.
