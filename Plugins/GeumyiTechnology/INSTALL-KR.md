# Geumyi Technology v0.1.0 설치 안내

## 1. 플러그인
`GeumyiTechnology-0.1.0.jar` → 서버의 `plugins/` 폴더

GeumyiChemistry 0.4.0은 선택 사항입니다. 같이 설치하면 고급 화학 연동 제작/전기분해가 활성화됩니다.

서버를 완전히 재시작하세요. PlugMan류 핫리로드는 권장하지 않습니다.

## 2. Bedrock / Geyser — 기존 Chemistry 팩을 유지하는 경우 (권장)
기존 Chemistry 파일은 그대로 두고 아래 2개를 추가합니다.

- `GeumyiTechnology-BE-0.1.0.mcpack` → `plugins/Geyser-Spigot/packs/`
- `GeumyiTechnology-Geyser-mappings-0.1.0.json` → `plugins/Geyser-Spigot/custom_mappings/`

Geyser 설정에서 `enable-custom-content: true`를 확인하고 서버를 완전 재시작합니다.

## 3. Bedrock / Geyser — Chemistry+Technology 통합 팩으로 교체하는 경우
기존 GeumyiChemistry BE 팩/매핑과 Technology 개별 팩/매핑을 제거한 뒤:

- `GeumyiSuite-BE-Chem0.4-Tech0.1.mcpack` → `plugins/Geyser-Spigot/packs/`
- `GeumyiSuite-Geyser-mappings-Chem0.4-Tech0.1.json` → `plugins/Geyser-Spigot/custom_mappings/`

**Tech-only 매핑과 Suite 매핑을 동시에 넣지 마세요.** 같은 Technology 정의가 두 번 등록될 수 있습니다.

## 4. Java 리소스팩
Chemistry 0.4와 같이 쓰면 `GeumyiSuite-JE-Chem0.4-Tech0.1.zip`을 권장합니다.
Technology만 쓴다면 `GeumyiTechnology-JE-0.1.0.zip`을 사용합니다.

Java 서버에서 자동 배포하려면 ZIP을 HTTP(S)로 접근 가능한 곳에 올리고 `server.properties`의 resource-pack URL에 지정합니다. 체크섬은 `CHECKSUMS.txt`에 있습니다.

## 5. 첫 테스트
1. `/plugins`에서 GeumyiTechnology가 활성화됐는지 확인
2. `/gtech give <닉네임> tech_manual`
3. 매뉴얼 우클릭 → 메인 GUI
4. `/gtech give <닉네임> tech_workbench`
5. 작업대 설치 → 우클릭 → 조립 GUI
6. 석탄 발전기, 케이블, 배터리, 분쇄기를 일렬로 설치
7. 석탄 발전기 GUI에서 석탄 투입
8. `/gtech status`로 전력 증가 확인
9. 분쇄기에서 조약돌 → 자갈 테스트
10. Bedrock에서도 2~9 반복

## 6. 문제 발생 시 보낼 로그
- 서버 시작부터 `GeumyiTechnology ... enabled`가 나오는 부분
- 오류 stack trace 전체
- `/version`
- `/geyser version`
- 문제가 난 장치 종류와 Java/Bedrock 여부
