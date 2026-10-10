# Archived one-shot GitHub Actions workflows

On 2026-10-11 the operator requested a major cleanup of experimental CI history and workflow clutter after small-server operational closeout.

- Exactly **36** inactive, Day10–12 one-shot test/diagnostic/build-preview YAML definitions were moved **byte-for-byte by existing Git blob SHA** from `.github/workflows/<name>.yml` to `docs/archive/workflows/<name>.yml.txt`, in a **single atomic Git tree commit** `041acec422211ec511dc1d357aa18fb44643e680`.
- This removed their automatic push/workflow-dispatch registration while retaining the full historical source for later review or restoration. No workflow source contents were rewritten and no runtime binaries were touched.
- Exactly **19** workflows were left active at the moment of the initial archive. After three SUCCESS rounds of GitHub CI/release/branch pruning, the one-time cleanup workflow itself was also moved to this archive, leaving **18 active workflows and 37 archived YAML sources**. The core System CI, host/Android/iOS builders, signed release, security, DR, read-only safety, and recovery workflows are retained.
- The one-time full-document reorganization workflow was subsequently archived as **the 38th** YAML source after [successful documentation migration](https://github.com/geumyi22/Geumyi-Minecraft-System/actions/runs/38082092641). Active workflow counts can change when new release/build workflows are added; 18 above is the historical post-cleanup snapshot, not a permanent active-workflow count.
- To restore a needed job in the future, copy its `.yml.txt` bytes back under `.github/workflows/<name>.yml`, then review its dependencies and permissions before enabling it. **Do not** blindly restore a security or release experiment into an always-on production CI workflow.
- Historic workflow run IDs in the source documentation may point to runs deliberately deleted by the closeout cleanup. Preserve pinned/important evidence according to `docs/archive/2026-10-11-before-cleanup-inventory.json` and the `geumyi-closeout-audit` Actions artifact.

The repository's `main` commit history has not been force-pushed or rewritten, and original signed baseline release tags have not been deleted.
