# GSC Velocity Control 1.0.0

GSC 개인용 서버 관리 화면에서 기존 Windows Scheduled Tasks 소유 Velocity를 정상 종료하기 위한 작은 로컬 플러그인입니다. 실행 소유권과 작업 정의를 바꾸지 않습니다. Paper 서버나 월드에는 설치하지 않습니다.

## 사용 흐름

1. GSC에서 **기존 프록시 찾기**로 wild/playground/other를 등록합니다.
2. 처음 한 번은 해당 프록시를 기존 콘솔의 `shutdown`으로 정상 종료합니다. 콘솔에 접근할 수 없다면 기존 운영 방식으로 안전하게 중지한 뒤 진행해야 하며, 이 플러그인이 실행 중인 기존 JVM에 자동 삽입되지는 않습니다.
3. **연결 준비**는 정확한 기존 Scheduler 작업·실행 폴더를 확인하고 작업 중지 및 TCP/UDP/제어 포트 해제를 확인한 경우에만 JAR와 인증 설정을 생성합니다. 기존 내용이 다르면 덮어쓰지 않습니다. 실행 중 설치, 작업 종료·비활성화, 작업 정의 변경은 하지 않습니다.
4. **시작**은 같은 기존 작업에 `/Run`을 요청합니다. 이후부터 접속자가 없을 때 **정상 종료** 또는 **재시작**을 사용할 수 있습니다.

종료는 Velocity API `ProxyServer.shutdown()`입니다. `taskkill`, 강제 종료, `schtasks /End`는 사용하지 않습니다. 명령 수락과 실제 프로세스 종료는 별도로 확인하며, 종료 확인 실패나 Scheduler 자동 재실행 시 재시작하지 않습니다. 시작 응답 확인이 실패했을 때도 이미 시작된 프로세스를 강제로 종료하지 않습니다. 일반 명령 콘솔이나 원격 명령 실행 기능은 없습니다.

## 로컬 연결과 파일

- `127.0.0.1`의 프로필별 포트(기본 28901~28903)에만 바인딩합니다.
- 모든 HTTP 요청에 별도의 256비트 토큰을 요구합니다. 토큰 비교는 상수 시간이며 Origin 헤더가 있는 브라우저 요청은 거절합니다. 상태 요청도 인증이 필요합니다.
- `GET /status`: 현재 PID, 시작 시각, 작업 폴더, 실제 Java 포트, 접속자 수 및 종료 진행 상태.
- `POST /shutdown`: 현재 PID·시작 시각 일치 및 접속자 0명일 때만 수락. 응답을 보낸 뒤 정상 종료합니다. 새 로그인은 종료 진행 중 차단하고, 이미 진행하던 로그인이 완료되면 종료를 취소합니다.
- 비밀 파일: GSC 설정 옆 `instance-secrets/<id>.json`, 프록시의 `plugins/gscvelocitycontrol/control.properties`. 이 파일은 공유하거나 저장소에 올리지 마세요. 생성 시 SYSTEM 및 Administrators 전용 디렉터리를 사용합니다. API 응답에 토큰은 포함하지 않습니다.
- 설정이 없거나 잘못됐거나 제어 포트가 사용 중이면 **제어 기능만 비활성화**됩니다. 프록시 종료나 설정 자동 생성은 하지 않습니다.

지원 대상은 기존 `Geumyi Day10 Velocity wild/playground/other` 작업입니다. 원본 `tools/day10/finish_four_servers.ps1`처럼 SYSTEM, 절대 Java 실행 경로, 해당 FourServer 작업 폴더, `-jar velocity.jar` 직접 실행 구성을 확인합니다. 다른 시작 방식은 자동 추정하지 않습니다.

## 빌드

```powershell
.\build.ps1 -JdkHome 'C:\Program Files\Java\jdk-27.0.1.0.3'
```

공식 PaperMC Maven 저장소의 `velocity-api:4.2.0`, Maven Central의 Guice 7.0.0, Adventure 5.2.0, SLF4J 2.0.19를 컴파일 전용으로 사용합니다. 의존성을 JAR에 중복 포함하지 않습니다. JDK 25 이상으로 컴파일하고 `--release 17` 바이트코드를 생성합니다. 실제 JVM 최소 버전은 사용하는 Velocity 버전의 요구사항도 만족해야 합니다. 이전 Velocity 버전과의 실제 호환성은 별도 확인하지 않았습니다.

결과는 Host의 `cmd/host/assets/gsc-velocity-control.jar`에 생성되어 `go:embed`로 포함됩니다. 고정 JAR 타임스탬프를 사용합니다. `*.jar` 제외 규칙이 있으므로 해당 임베드 자산만 명시적으로 버전 관리해야 합니다.

공식 API 문서: https://docs.papermc.io/velocity/dev/api-basics/

빌드·기본 검증과 운영 서버 적용은 별개입니다. 실제 세 프록시의 설치·종료·재시작과 Java/Bedrock 접속은 사용자가 확인해야 합니다.
