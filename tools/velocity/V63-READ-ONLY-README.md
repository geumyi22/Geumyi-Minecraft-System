# 금이 서버 GSC 4.5.2 — Velocity V6.3 읽기 전용 진단

**목적:** 이전 V6.2에서 확인한 3개 Scheduler Java 후보 + 다른 Java 설치 경로의 UDP 소유 Velocity 3개 및 TCP 리스너 0개 현상의 원인을 좁힙니다. V6.2 스냅샷, 기존 보호된 원본 작업 XML, Canary Host 설치를 반복하지 않습니다.

1. ZIP을 Downloads 같은 별도 폴더에 풀고 `Run_GSC452_Velocity_Origin_V63_READ_ONLY.cmd`를 **관리자 권한으로 실행**합니다.
2. 한 줄로 나오는 **정제된 JSON만** 대화에 보내세요. `schema=8`, `synthetic=false`, `diagnostic_revision=6.3-origin-read-only` 확인.
3. 실제 PID, Java 명령줄, 로그 내용, 토큰/키, 작업 XML, 세부 경로를 올리지 마세요.

## 알아둘 점

- `C:\ProgramData\GeumyiServerCenter\Network\FourServer\{wild,playground,other}`의 예약 작업 실행 폴더, `velocity.toml`의 bind 라인 및 그 폴더의 `logs/latest.log`, `logs/velocity.log` 중 있는 파일의 마지막 300줄만 **읽습니다**. 로그 내용은 출력하지 않으며 기계적으로 상태만 분류합니다. 실제 Paper 월드가 있는 OneDrive는 조회하지 않습니다.
- 로그가 최근 30분 이내에 수정됐는지 구분합니다. `STALE_OR_CLOCK_UNVERIFIED`는 현재 장애의 원인으로 단정하지 않습니다.
- `RELATIVE_JAR_CWD_NOT_PROVEN`은 `-jar velocity.jar`를 의미하며 **실행 중 JVM의 실제 현재 작업 폴더는 확인할 수 없다**는 뜻입니다.
- `WINDOWS_SERVICE_OR_TASK_HOST_HINT`, `NEAR_LAST_RUN_HINT_ONLY`는 힌트이지 Scheduler 작업→JVM 소유권의 증거가 아닙니다.
- 관리자 권한에서도 보호된 파일 접근이 거부될 수 있습니다. 별도 ACL 변경이나 소유권 가져오기 절대 하지 마세요.
- 코드에는 `Start/Stop-ScheduledTask`, `Start/Stop-Process`, `Set-Acl`, 서버 재시작, 포트 변경, 레지스트리 변경, 파일 쓰기 동작이 없습니다.
- 모든 `safe_to_stop`, `safe_to_cutover`, `live_control_authorized`, `task_to_jvm_ownership_proven`은 항상 `false`입니다. GSC Host 4.5.2 Canary와 기존 Scheduler 작업을 유지합니다.
- Windows 전용 CI는 제공된 워크플로를 GitHub에서 실제 실행하고 PASS를 확인하기 전까지 **미검증**입니다. 합성 테스트 PASS도 사용자 실서버 검증이 아닙니다.

**종료코드:** 0 = 조회 완료(소유권은 여전히 미확정), 2 = 불완전/읽기 실패, 3 = 관리자 권한 필요, 4 = Windows/ProgramData 경로 오류.
