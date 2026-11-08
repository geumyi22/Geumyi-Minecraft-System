# Build GSC 5.0.0

Requires Go 1.23.2 or compatible on Windows. Run `powershell -File build.ps1`.

The original installer embeds payload files. Before building, restore these exact versioned JARs to `cmd/setup/payload/` from the existing [mc-2026.09.26-v3 release](https://github.com/geumyi22/Geumyi-Minecraft-System/releases/tag/mc-2026.09.26-v3):

- GeumyiStatusAgent-0.5.4.jar (inside the GSC FINAL archive / Agent bundle)
- GeumyiServerTools-1.1.1-SpigotPaper26.3-GSCv4.1-HOTFIX.jar
- GeumyiDiscordStatus-1.1.1-SpigotPaper26.3.jar

The build script compiles Host and Client EXEs from this source before embedding them into Setup. JARs/EXEs remain ignored; do not commit payload binaries or configured credentials. Existing placeholder-only managed templates remain because the installer reads those exact paths.

Run `go test ./...` for the recovered unit tests. Building the complete installer still requires the release payloads above.

Version 5.0.0 is the personal operator-accepted Stable candidate built on the PR61 hardening source. It retains the compatible v4 API and external Windows Scheduler Velocity ownership. Only freshly built artifacts from the exact reviewed commit are eligible; never relabel old binaries. The personal acceptance ledger distinguishes automated checks, operator confirmation, accepted limitations and unexecuted tests. The full Day12 production closure gates remain unchanged.

The personal release workflow first rebuilds and verifies Windows artifacts and stages an Ed25519-signed GSC-only Draft. A separate explicit publication dispatch rechecks that Draft and its completed source CI run. Manifest signing is not Windows Authenticode signing. Installation and live update discovery require their own verification.
