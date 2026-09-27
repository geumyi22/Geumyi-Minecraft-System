# GeumyiChemistry v0.4.0 설치 가이드

## 1. 플러그인
1. Paper 서버를 완전히 종료합니다.
2. 이전 `GeumyiChemistry-0.3.0.jar` 또는 다른 구버전 JAR을 `plugins/`에서 삭제합니다.
3. `GeumyiChemistry-0.4.0.jar`를 `plugins/`에 넣습니다.
4. `plugins/GeumyiChemistry/` 데이터 폴더는 삭제하지 않아도 됩니다.

## 2. Bedrock / Geyser
Geyser-Spigot 기준:

- `GeumyiChemistry-BE-0.4.0.mcpack`
  -> `plugins/Geyser-Spigot/packs/GeumyiChemistry-BE-0.4.0.mcpack`
- `GeumyiChemistry-Geyser-mappings-0.4.0.json`
  -> `plugins/Geyser-Spigot/custom_mappings/GeumyiChemistry-Geyser-mappings-0.4.0.json`

Geyser 설정에서 다음 옵션이 켜져 있어야 합니다.

```yaml
enable-custom-content: true
```

`resource-pack-urls: []`은 그대로 두어도 됩니다. 이번 Bedrock 팩은 로컬 `packs` 폴더 방식으로 로드할 수 있습니다.

## 3. Java 리소스팩
`GeumyiChemistry-JE-0.4.0.zip`을 각 Java 클라이언트의 resourcepacks 폴더에 넣고 활성화하면 바로 사용할 수 있습니다.

서버에서 자동 배포하려면 ZIP을 클라이언트가 다운로드 가능한 HTTPS 주소에 올린 뒤 `server.properties`를 설정합니다.

```properties
resource-pack=<JE ZIP의 직접 다운로드 HTTPS URL>
resource-pack-sha1=<CHECKSUMS.txt의 JE_RESOURCE_PACK_SHA1>
require-resource-pack=true
```

`resource-pack-id`는 필요하다면 UUID를 별도로 정해 사용할 수 있습니다. URL은 서버 로컬 파일 경로가 아니라 클라이언트가 접근 가능한 직접 다운로드 URL이어야 합니다.

## 4. 재시작 및 확인
서버/Geyser를 완전히 재시작한 뒤 다음을 확인하세요.

1. 콘솔에 `GeumyiChemistry 0.4.0 enabled`가 출력되는지
2. `/chem`이 열리는지
3. `/chem recipe`에서 화학 실험 키트/장비 제작법이 보이는지
4. Java에서 전용 화학 아이콘이 보이는지
5. Bedrock에서 전용 화학 아이콘이 보이는지
6. Bedrock의 설치형 화학 실험대는 Brewing Stand 아이콘으로 보이지만 설치 후 우클릭으로 연구실이 열리는지
7. 추출기와 기체/앙금/전기분해 반응이 정상 처리되는지

## 5. 첫 테스트 추천
관리자 권한에서 빠르게 확인하려면:

```text
/chem givetool <닉네임> lab_kit
/chem givetool <닉네임> lab_bench
/chem givetool <닉네임> gas_collector
/chem give <닉네임> H2 2
/chem give <닉네임> O2 1
```

그 뒤 실험 키트 -> 기체 실험실에서 조건을 맞춰 반응 테스트를 하면 됩니다.

## 주의
실제 서버에서 문제가 생겼을 때 구버전 JAR과 v0.4 JAR이 동시에 `plugins/`에 존재하는지 먼저 확인하세요. 같은 플러그인 이름의 JAR이 두 개 있으면 정상 로딩을 보장할 수 없습니다.
