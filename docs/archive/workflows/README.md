# Archived one-shot GitHub Actions workflows

On 2026-10-11 the operator requested a major cleanup of experimental CI history and workflow clutter after small-server operational closeout.

- Exactly **36** inactive, Day10–12 one-shot test/diagnostic/build-preview YAML definitions were moved **byte-for-byte by existing Git blob SHA** from `.github/workflows/<name>.yml` to `docs/archive/workflows/<name>.yml.txt`, in a **single atomic Git tree commit** `041acec422211ec511dc1d357aa18fb44643e680`.
- This removed their automatic push/workflow-dispatch registration while retaining the full historical source for later review or restoration. No workflow source contents were rewritten and no runtime binaries were touched.
- Exactly **19** workflows were left active at the moment of the initial archive. After three SUCCESS rounds of GitHub CI/release/branch pruning, the one-time cleanup workflow itself was also moved to this archive, leaving **18 active workflows and 37 archived YAML sources**. The core System CI, host/Android/iOS builders, signed release, security, DR, read-only safety, and recovery workflows are retained.
- The one-time full-document reorganization workflow was subsequently archived as **the 38th** YAML source after [successful documentation migration](https://github.com/geumyi22/Geumyi-Minecraft-System/actions/runs/38082092641). Active workflow counts can change when new release/build workflows are added; 18 above is the historical post-cleanup snapshot, not a permanent active-workflow count.
- To restore a needed job in the future, copy its `.yml.txt` bytes back under `.github/workflows/<name>.yml`, then review its dependencies and permissions before enabling it. **Do not** blindly restore a security or release experiment into an always-on production CI workflow.
- Historic workflow run IDs in the source documentation may point to runs deliberately deleted by the closeout cleanup. Preserve pinned/important evidence according to `docs/archive/2026-10-11-before-cleanup-inventory.json` and the `geumyi-closeout-audit` Actions artifact.

## 2026-10-11 패키지 공개 후 추가 보관

- [공개 워크플로 SUCCESS](https://github.com/geumyi22/Geumyi-Minecraft-System/actions/runs/38082558818) 이후 게시 일회성 정의 `ops-publish-packaged-stable-once.yml.txt`를 보관했습니다.
- 중복 빌드/구버전 Stable 발행을 막기 위해 `release-gsc450-gscm150-stable.yml`, `ops-stable-baseline-publish-once.yml`도 각 `.yml.txt`로 **원본 Git blob SHA 그대로** 보관하고 활성 디렉터리에서 제외했습니다.
- 이 작업 후 활성 워크플로 **18개**, 보관된 워크플로 YAML 소스 **41개**. 정식 보안 게이트 워크플로, 공통 빌더, 다른 운영 CI는 그대로 유지합니다.

The repository's `main` commit history has not been force-pushed or rewritten, and original signed baseline release tags have not been deleted.

## 2026-10-11 — 4.5.1 / 1.5.1+151 공개 후 추가 보관

- [4.5.1/1.5.1+151 최신 릴리즈](https://github.com/geumyi22/Geumyi-Minecraft-System/releases/tag/system-2026.10.11-stable-gsc451-gscm151)는 [후속 공개 CI](https://github.com/geumyi22/Geumyi-Minecraft-System/actions/runs/38085210886)에서 정상 공개됐습니다.
- 배포 전용 `release-gsc451-gscm151-once.yml`, `ops-publish-gsc451-gscm151-once.yml` 두 개를 같은 Git blob SHA로 `docs/archive/workflows/`에 `.yml.txt` 형태로 보관했습니다. 기존 릴리즈/태그/CI 이력은 삭제하지 않았습니다.
- 이 정리 시점의 활성 `.yml` 워크플로는 **18개**, 아카이브 `.yml.txt`는 **43개**입니다. 이후 추가 작업에 따라 숫자가 달라질 수 있습니다.

## 2026-10-11 — GSC 4.5.1 서명 Beta 1회 게시 워크플로 보관

- [서명 Beta 공개 CI](https://github.com/geumyi22/Geumyi-Minecraft-System/actions/runs/38089609727) SUCCESS 및 [릴리즈](https://github.com/geumyi22/Geumyi-Minecraft-System/releases/tag/system-2026.10.11-gsc451-signed-beta.1) 공개·검증 후 `ops-publish-gsc451-signed-beta-once.yml`을 동일 Git blob으로 `.yml.txt` 보관했습니다.
- Stable 보안 검증 승인, 서비스 자동 설치, 플러그인 업데이트, 운영 서버 상태 변경을 수행하지 않았습니다.
